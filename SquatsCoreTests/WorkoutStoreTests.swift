import Foundation
import Testing
@testable import SquatsCore

let monday = TestCalendar.date("2026-09-28", hour: 10)

func dates(_ workouts: [Workout]) -> [String] {
    workouts.map { TestCalendar.string($0.scheduledDate) }
}

@MainActor
struct SchedulingTests {
    @Test func createFillsSelectedDaysAhead() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(planned.count == 37) // 12 weeks × 3 + Monday Dec 21
        #expect(dates(Array(planned.prefix(4))) == ["2026-09-28", "2026-09-30", "2026-10-02", "2026-10-05"])
        #expect(planned.map(\.sessionIndex) == Array(0..<37))
        #expect(Set(planned.map(\.id)).count == 37)
    }

    @Test func generatedIDsAreDeterministic() {
        let program = makeProgram()
        let first = makeStore()
        first.createProgram(program, now: monday)
        let second = makeStore()
        second.createProgram(program, now: monday)
        #expect(first.workouts.map(\.id) == second.workouts.map(\.id))
    }

    @Test func refreshIsIdempotent() {
        let store = makeStore()
        store.createProgram(makeProgram(), now: monday)
        let before = store.workouts
        store.refresh(now: monday)
        #expect(store.workouts == before)
    }

    @Test func movingOneWorkoutResequences() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let second = store.plannedWorkouts(programID: program.id)[1]
        store.reschedule(workoutID: second.id, to: TestCalendar.date("2026-10-03"), shiftFollowing: false, now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(4))) == ["2026-09-28", "2026-10-02", "2026-10-03", "2026-10-05"])
        #expect(planned[2].id == second.id)
        #expect(store.header(for: planned[1])?.liftNames == ["Deadlift"])
        #expect(store.program(program.id)?.schedule.weekdays == monWedFri)
    }

    @Test func shiftingFollowingMovesEverythingAndKeepsNewDays() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.reschedule(workoutID: first.id, to: TestCalendar.date("2026-09-29"), shiftFollowing: true, now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(3))) == ["2026-09-29", "2026-10-01", "2026-10-03"])
        #expect(planned.count == 37)
        #expect(store.program(program.id)?.schedule.weekdays == [Weekday.tuesday, Weekday.thursday, Weekday.saturday])

        // New workouts generated later continue on the shifted days.
        store.refresh(now: TestCalendar.date("2026-10-12", hour: 9))
        let tail = store.plannedWorkouts(programID: program.id).suffix(6)
        let weekdays = Set(tail.map { TestCalendar.calendar.component(.weekday, from: $0.scheduledDate) })
        #expect(weekdays == [Weekday.tuesday, Weekday.thursday, Weekday.saturday])
    }

    @Test func restAnotherDay() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)

        store.restAnotherDay(workoutID: planned[0].id, shiftFollowing: false, now: monday)
        #expect(dates(Array(store.plannedWorkouts(programID: program.id).prefix(3))) == ["2026-09-29", "2026-09-30", "2026-10-02"])

        let other = makeStore()
        let program2 = other.createProgram(makeProgram(), now: monday)
        let first = other.plannedWorkouts(programID: program2.id)[0]
        other.restAnotherDay(workoutID: first.id, shiftFollowing: true, now: monday)
        #expect(dates(Array(other.plannedWorkouts(programID: program2.id).prefix(3))) == ["2026-09-29", "2026-10-01", "2026-10-03"])
    }

    @Test func restAnotherDayOnOverdueWorkoutMovesPastToday() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        let tuesday = TestCalendar.date("2026-09-29", hour: 8)
        store.restAnotherDay(workoutID: first.id, shiftFollowing: false, now: tuesday)
        #expect(TestCalendar.string(store.workout(first.id)!.scheduledDate) == "2026-09-30")
    }

    @Test func startEarlyPullsFollowingForward() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(weekdays: [Weekday.tuesday, Weekday.thursday, Weekday.saturday]), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        #expect(TestCalendar.string(first.scheduledDate) == "2026-09-29")

        store.startEarly(workoutID: first.id, shiftFollowing: true, now: monday)
        #expect(store.workout(first.id)?.status == .inProgress)
        #expect(TestCalendar.string(store.workout(first.id)!.scheduledDate) == "2026-09-28")
        #expect(dates(Array(store.plannedWorkouts(programID: program.id).prefix(2))) == ["2026-09-30", "2026-10-02"])
        #expect(store.program(program.id)?.schedule.weekdays == monWedFri)
    }

    @Test func startEarlyWithoutShifting() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(weekdays: [Weekday.tuesday, Weekday.thursday, Weekday.saturday]), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startEarly(workoutID: first.id, shiftFollowing: false, now: monday)
        #expect(TestCalendar.string(store.workout(first.id)!.scheduledDate) == "2026-09-28")
        #expect(dates(Array(store.plannedWorkouts(programID: program.id).prefix(1))) == ["2026-10-01"])
    }

    @Test func shiftWholeProgramBothWays() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        store.shiftProgram(programID: program.id, days: 7, now: monday)
        #expect(dates(Array(store.plannedWorkouts(programID: program.id).prefix(2))) == ["2026-10-05", "2026-10-07"])
        store.shiftProgram(programID: program.id, days: -1, now: monday)
        #expect(dates(Array(store.plannedWorkouts(programID: program.id).prefix(2))) == ["2026-10-04", "2026-10-06"])
        #expect(store.program(program.id)?.schedule.weekdays == [Weekday.sunday, Weekday.tuesday, Weekday.thursday])
        #expect(store.plannedWorkouts(programID: program.id).first?.sessionIndex == 0)
    }

    @Test func changingWeekdaysReplans() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        store.updateWeekdays(programID: program.id, to: [Weekday.tuesday, Weekday.thursday, Weekday.saturday], now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(3))) == ["2026-09-29", "2026-10-01", "2026-10-03"])
        #expect(Set(planned.map(\.scheduledDate)).count == planned.count)

        // The day count is fixed by the program.
        store.updateWeekdays(programID: program.id, to: [Weekday.monday], now: monday)
        #expect(store.program(program.id)?.schedule.weekdays.count == 3)
    }

    @Test func skippingKeepsProgramStep() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.skipWorkout(planned[0].id, now: monday)
        let next = store.nextWorkout(programID: program.id)
        #expect(next?.id == planned[1].id)
        #expect(next?.sessionIndex == 0)
        #expect(store.header(for: next!)?.liftNames == ["Squat", "Bench Press"])
        #expect(store.workout(planned[0].id)?.header?.title == "Week 1 · 5s")
    }

    @Test func startedWorkoutsKeepTheirSlot() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[1].id, now: monday)
        #expect(store.workout(planned[1].id)?.sessionIndex == 1)
        #expect(store.workout(planned[0].id)?.sessionIndex == 0)
        #expect(store.workout(planned[2].id)?.sessionIndex == 2)
        store.discardWorkout(planned[1].id)
        #expect(store.workout(planned[1].id)?.status == .planned)
        #expect(store.workout(planned[1].id)?.sets.isEmpty == true)
    }

    @Test func currentWorkoutAndRestDays() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(store.currentWorkout(programID: program.id, now: monday)?.id == planned[0].id)
        let tuesday = TestCalendar.date("2026-09-29", hour: 9)
        store.startWorkout(planned[0].id, now: monday)
        store.completeWorkout(planned[0].id, now: monday)
        #expect(store.currentWorkout(programID: program.id, now: tuesday) == nil)
        #expect(store.nextWorkout(programID: program.id)?.id == planned[1].id)
    }

    @Test func missedAfterGraceDay() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]

        let tuesday = TestCalendar.date("2026-09-29", hour: 9)
        store.refresh(now: tuesday)
        #expect(store.displayStatus(of: store.workout(first.id)!, now: tuesday) == .overdue)
        #expect(store.workoutsAtRisk(now: tuesday).map(\.id) == [first.id])

        let wednesday = TestCalendar.date("2026-09-30", hour: 9)
        store.refresh(now: wednesday)
        #expect(store.workout(first.id)?.missedOn != nil)
        #expect(store.displayStatus(of: store.workout(first.id)!, now: wednesday) == .missed)
    }

    @Test func archiveDropsPlanButKeepsHistory() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        _ = completeNext(store, programID: program.id, now: monday)
        store.archiveProgram(program.id)
        #expect(store.plannedWorkouts(programID: program.id).isEmpty)
        #expect(store.history(programID: program.id).count == 1)
        #expect(store.deletions.count == 36)
        store.refresh(now: monday)
        #expect(store.plannedWorkouts(programID: program.id).isEmpty)
    }
}

@MainActor
struct WorkoutSessionTests {
    @Test func startFreezesExpectedAndPrefillsActual() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: monday)
        let started = store.workout(first.id)!
        #expect(started.status == .inProgress)
        #expect(started.sets.count == 22)
        let squatMain = started.sets.filter { $0.liftID == "squat" && $0.kind == .main }
        #expect(squatMain.map(\.targetWeight) == [65, 75, 85])
        #expect(squatMain.map(\.weight) == [65, 75, 85])
        #expect(squatMain.last?.isAMRAP == true)

        store.adjustTrainingMax(programID: program.id, liftID: "squat", to: 200, now: monday)
        #expect(store.workout(first.id)?.sets.filter { $0.liftID == "squat" && $0.kind == .main }.map(\.weight) == [65, 75, 85])
    }

    @Test func actualCanDifferFromExpected() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: monday)
        let set = store.workout(first.id)!.sets.first { $0.kind == .main }!
        store.updateSet(workoutID: first.id, setID: set.id) { $0.weight = 62.5; $0.reps = 4 }
        store.toggleSet(workoutID: first.id, setID: set.id, now: monday)
        let updated = store.workout(first.id)!.sets.first { $0.id == set.id }!
        #expect(updated.targetWeight == 65)
        #expect(updated.weight == 62.5)
        #expect(updated.missedTarget)
    }

    @Test func completionSummary() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let summary = completeNext(store, programID: program.id, now: monday, amrapReps: 8)!
        #expect(summary.completedSets == 22)
        #expect(summary.lifts.map(\.liftID) == ["squat", "bench"])
        let squat = summary.lifts[0]
        #expect(squat.amrapReps == 8)
        #expect(squat.amrapTarget == 5)
        #expect(squat.estimatedOneRepMax == 107.644)
        #expect(summary.streak == 1)
        #expect(summary.completedCycle == nil)
        #expect(summary.suggestions.isEmpty)
    }

    @Test func finishingCycleReportsNextTrainingMaxes() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        var last: CompletionSummary?
        for _ in 0..<9 { last = completeNext(store, programID: program.id, now: monday, amrapReps: 6) }
        #expect(last?.completedCycle == 0)
        #expect(last?.nextTrainingMaxes.map(\.trainingMax) == [105, 62.5, 145])
        #expect(last?.suggestions.isEmpty == true)
        #expect(store.trainingMaxes(programID: program.id).map(\.trainingMax) == [105, 62.5, 145])
    }

    @Test func stalledCycleSuggestsReset() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        var last: CompletionSummary?
        for _ in 0..<9 { last = completeNext(store, programID: program.id, now: monday, amrapReps: 0) }
        let squat = last?.suggestions.first { $0.liftID == "squat" }
        #expect(squat?.reason == .stalled)
        #expect(squat?.suggestedTrainingMax == 85)
        #expect(last?.suggestions.first { $0.liftID == "bench" }?.suggestedTrainingMax == 52.5)

        store.apply(squat!, programID: program.id)
        #expect(store.trainingMaxes(programID: program.id).first { $0.liftID == "squat" }?.trainingMax == 85)
    }

    @Test func failedTrainingMaxTestSuggestsReset() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        for _ in 0..<27 { _ = completeNext(store, programID: program.id, now: monday, amrapReps: 6) }
        let test = completeNext(store, programID: program.id, now: monday, amrapReps: 2)!
        #expect(test.isTestWeek)
        // 115 × 2 → e1RM 122.659 → 90% = 110.39 → 110
        #expect(test.suggestions.map(\.suggestedTrainingMax) == [110])
        #expect(test.suggestions.first?.reason == .failedTest)

        let passed = completeNext(store, programID: program.id, now: monday, amrapReps: 4)!
        #expect(passed.suggestions.isEmpty)
    }

    @Test func accessoriesUsePreviousAsExpected() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: monday)
        let accessoryID = store.addAccessory(to: planned[0].id, named: "  Face Pulls ")!
        let sets = store.workout(planned[0].id)!.accessories[0].sets
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.targetReps == nil })
        for (set, reps) in zip(sets, [15, 12, 10]) {
            store.updateAccessorySet(workoutID: planned[0].id, accessoryID: accessoryID, setID: set.id) { $0.weight = 20; $0.reps = reps }
        }
        store.addAccessorySet(workoutID: planned[0].id, accessoryID: accessoryID)
        #expect(store.workout(planned[0].id)!.accessories[0].sets.map(\.reps) == [15, 12, 10, 10])
        store.completeWorkout(planned[0].id, now: monday)

        store.startWorkout(planned[1].id, now: monday)
        store.addAccessory(to: planned[1].id, named: "face pulls")
        let prefilled = store.workout(planned[1].id)!.accessories[0]
        #expect(prefilled.name == "Face Pulls")
        #expect(prefilled.sets.map(\.targetReps) == [15, 12, 10, 10])
        #expect(prefilled.sets.map(\.reps) == [15, 12, 10, 10])
        #expect(prefilled.sets.allSatisfy { $0.targetWeight == 20 && !$0.isCompleted })
    }

    @Test func persistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorkoutStore(fileURL: url, calendar: TestCalendar.calendar)
        let program = store.createProgram(makeProgram(), now: monday)
        store.startWorkout(store.plannedWorkouts(programID: program.id)[0].id, now: monday)
        var saves = 0
        store.onDidSave = { saves += 1 }
        store.saveNow()
        #expect(saves == 1)

        let reloaded = WorkoutStore(fileURL: url, calendar: TestCalendar.calendar)
        #expect(reloaded.programs == store.programs)
        #expect(reloaded.workouts == store.workouts)
        #expect(reloaded.exercises == store.exercises)
        #expect(reloaded.lastError == nil)
    }

    @Test func unreadableDataIsSetAside() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("data.json")
        try Data("not json".utf8).write(to: url)

        let store = WorkoutStore(fileURL: url, calendar: TestCalendar.calendar)
        #expect(store.lastError != nil)
        #expect(store.programs.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("data.unreadable-") })
    }
}

@MainActor
struct ExerciseLibraryTests {
    @Test func seededWithBuiltIns() {
        let store = makeStore()
        #expect(store.visibleExercises.count == ExerciseCatalog.builtIns.count)
        #expect(store.exercise(named: "lateral raises")?.category == .push)
    }

    @Test func addRemoveRestore() {
        let store = makeStore()
        let custom = store.addExercise(named: " Nordic Curls ", category: .singleLegCore)!
        #expect(custom.name == "Nordic Curls")
        #expect(store.addExercise(named: "nordic curls", category: .singleLegCore)?.id == custom.id)

        store.removeExercise(custom.id)
        #expect(store.exercise(named: "Nordic Curls") == nil)
        #expect(store.deletions.map(\.id) == [custom.id])

        let dips = store.exercise(named: "Dips")!
        store.removeExercise(dips.id)
        #expect(!store.visibleExercises.contains { $0.id == dips.id })
        #expect(store.hiddenBuiltInExercises.map(\.id) == [dips.id])
        store.restoreBuiltInExercises()
        #expect(store.visibleExercises.contains { $0.id == dips.id })
    }

    @Test func quickAddRanksMostUsed() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        #expect(store.quickAddExercises().isEmpty)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: monday)
        store.addAccessory(to: planned[0].id, named: "Dips")
        store.addAccessory(to: planned[0].id, named: "Chin-ups")
        store.startWorkout(planned[1].id, now: monday.addingTimeInterval(86_400))
        store.addAccessory(to: planned[1].id, named: "Chin-ups")
        store.addAccessory(to: planned[1].id, named: "Sled Push")
        #expect(store.quickAddExercises().map(\.name) == ["Chin-ups", "Sled Push", "Dips"])
        #expect(store.exercise(named: "Sled Push")?.category == .other)
        #expect(store.usageCount(ofExerciseNamed: "chin-ups") == 2)
    }
}

@MainActor
struct StreakTests {
    @Test func completionsBuildStreakAndMissBreaksIt() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)

        store.startWorkout(planned[0].id, now: monday)
        store.completeWorkout(planned[0].id, now: monday.addingTimeInterval(3600))
        #expect(store.streak() == StreakSummary(current: 1, best: 1))

        let wednesday = TestCalendar.date("2026-09-30", hour: 18)
        store.startWorkout(planned[1].id, now: wednesday)
        store.completeWorkout(planned[1].id, now: wednesday.addingTimeInterval(3600))
        #expect(store.streak() == StreakSummary(current: 2, best: 2))

        store.refresh(now: TestCalendar.date("2026-10-04", hour: 9))
        #expect(store.streak() == StreakSummary(current: 0, best: 2))
    }

    @Test func reschedulingInTimeProtectsStreak() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: monday)
        store.completeWorkout(planned[0].id, now: monday)

        let wednesday = TestCalendar.date("2026-09-30", hour: 8)
        store.restAnotherDay(workoutID: planned[1].id, shiftFollowing: false, now: wednesday)
        let thursday = TestCalendar.date("2026-10-01", hour: 18)
        store.refresh(now: thursday)
        store.startWorkout(planned[1].id, now: thursday)
        store.completeWorkout(planned[1].id, now: thursday)
        #expect(store.streak().current == 2)
    }

    @Test func skippingByEndOfDayKeepsStreak() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: monday)
        store.completeWorkout(planned[0].id, now: monday)

        store.skipWorkout(planned[1].id, now: TestCalendar.date("2026-09-30", hour: 23))
        #expect(store.streak().current == 1)

        // Skipping Friday's workout on Saturday is too late.
        store.skipWorkout(planned[2].id, now: TestCalendar.date("2026-10-03", hour: 9))
        #expect(store.streak() == StreakSummary(current: 0, best: 1))
    }

    @Test func lateCompletionRestartsStreak() {
        let summary = StreakCalculator.summary(for: [
            Workout(programID: UUID(), sessionIndex: 0, scheduledDate: TestCalendar.date("2026-09-28"), status: .completed,
                    completedAt: TestCalendar.date("2026-09-28", hour: 9)),
            Workout(programID: UUID(), sessionIndex: 1, scheduledDate: TestCalendar.date("2026-09-30"), status: .completed,
                    completedAt: TestCalendar.date("2026-10-03", hour: 9), missedOn: TestCalendar.date("2026-09-30")),
        ])
        #expect(summary == StreakSummary(current: 1, best: 1))
    }
}
