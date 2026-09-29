import Foundation
import Testing
@testable import SquatsCore

@MainActor
struct SchedulingTests {
    let now = TestCalendar.date("2026-09-28", hour: 10) // a Monday

    func dates(_ workouts: [Workout]) -> [String] {
        workouts.map { TestCalendar.string($0.scheduledDate) }
    }

    @Test func createFillsSelectedDaysAhead() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(planned.count == 37) // 12 weeks × 3 + Monday Dec 21
        #expect(dates(Array(planned.prefix(4))) == ["2026-09-28", "2026-09-30", "2026-10-02", "2026-10-05"])
        #expect(planned.map(\.sessionIndex) == Array(0..<37))
        let weekdays = Set(planned.map { TestCalendar.calendar.component(.weekday, from: $0.scheduledDate) })
        #expect(weekdays == [Weekday.monday, Weekday.wednesday, Weekday.friday])
    }

    @Test func refreshIsIdempotent() {
        let store = makeStore()
        store.createProgram(makeProgram(), now: now)
        let before = store.workouts
        store.refresh(now: now)
        #expect(store.workouts == before)
    }

    @Test func movingOneWorkoutResequences() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let second = store.plannedWorkouts(programID: program.id)[1]
        // Wednesday's workout moved to Saturday: Friday's becomes the 2nd session.
        store.reschedule(workoutID: second.id, to: TestCalendar.date("2026-10-03"), scope: .onlyThis, now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(4))) == ["2026-09-28", "2026-10-02", "2026-10-03", "2026-10-05"])
        #expect(planned[2].id == second.id)
        #expect(planned[2].sessionIndex == 2)
        #expect(planned.count == 37)
    }

    @Test func shiftFollowingKeepsSpacing() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.reschedule(workoutID: first.id, to: TestCalendar.date("2026-09-29"), scope: .thisAndFollowing(.keepSpacing), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(3))) == ["2026-09-29", "2026-10-01", "2026-10-03"])
        #expect(planned.count == 37)
        #expect(Set(planned.map(\.scheduledDate)).count == planned.count)
    }

    @Test func shiftFollowingFitsWorkoutDays() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.reschedule(workoutID: first.id, to: TestCalendar.date("2026-09-29"), scope: .thisAndFollowing(.fitToSchedule), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(4))) == ["2026-09-29", "2026-09-30", "2026-10-02", "2026-10-05"])
        #expect(planned.count == 37)
        #expect(Set(planned.map(\.scheduledDate)).count == planned.count)
    }

    @Test func shiftWholeProgram() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        store.shiftProgram(programID: program.id, days: 7, now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(2))) == ["2026-10-05", "2026-10-07"])
        #expect(planned.count == 37)
        #expect(planned.first?.sessionIndex == 0)
    }

    @Test func changingScheduleReplansAndKeepsWeeks() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        store.updateSchedule(programID: program.id, to: WeeklySchedule(sessionsPerWeek: 2, weekdays: [Weekday.tuesday, Weekday.thursday]), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        #expect(dates(Array(planned.prefix(3))) == ["2026-09-29", "2026-10-01", "2026-10-06"])
        let weeks = planned.prefix(5).compactMap { store.header(for: $0)?.week }
        #expect(weeks == [0, 0, 1, 1, 2])
        #expect(Set(planned.map(\.scheduledDate)).count == planned.count)
    }

    @Test func skippingKeepsProgramStep() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(advanceMode: .perWorkout), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        store.skipWorkout(planned[0].id, now: now)
        let next = store.nextWorkout(programID: program.id)
        #expect(next?.id == planned[1].id)
        #expect(next?.sessionIndex == 0)
        #expect(store.header(for: next!)?.title == "Week 1 · 5s")
        #expect(store.workout(planned[0].id)?.header?.title == "Week 1 · 5s")
    }

    @Test func startedWorkoutsKeepTheirSlot() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(advanceMode: .perWorkout), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[1].id, now: now)
        #expect(store.workout(planned[1].id)?.sessionIndex == 1)
        #expect(store.workout(planned[0].id)?.sessionIndex == 0)
        #expect(store.workout(planned[2].id)?.sessionIndex == 2)
        store.discardWorkout(planned[1].id)
        #expect(store.workout(planned[1].id)?.status == .planned)
        #expect(store.workout(planned[1].id)?.sets.isEmpty == true)
    }

    @Test func missedAfterGraceDay() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
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
        let program = store.createProgram(makeProgram(), now: now)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: now)
        store.completeWorkout(first.id, now: now.addingTimeInterval(3600))
        store.archiveProgram(program.id)
        #expect(store.plannedWorkouts(programID: program.id).isEmpty)
        #expect(store.history(programID: program.id).count == 1)
        store.refresh(now: now)
        #expect(store.plannedWorkouts(programID: program.id).isEmpty)
    }
}

@MainActor
struct WorkoutSessionTests {
    let now = TestCalendar.date("2026-09-28", hour: 10)

    @Test func startFreezesPrescription() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: now)
        let started = store.workout(first.id)!
        #expect(started.status == .inProgress)
        #expect(started.sets.map(\.weight) == [40, 50, 60, 65, 75, 85])
        #expect(started.sets.last?.isAMRAP == true)

        // Changing the program later doesn't rewrite a started workout.
        store.adjustTrainingMax(programID: program.id, to: 200, now: now)
        #expect(store.workout(first.id)?.sets.map(\.weight) == [40, 50, 60, 65, 75, 85])
    }

    @Test func completionSummary() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let first = store.plannedWorkouts(programID: program.id)[0]
        store.startWorkout(first.id, now: now)
        for set in store.workout(first.id)!.sets {
            store.toggleSet(workoutID: first.id, setID: set.id, now: now)
        }
        let amrap = store.workout(first.id)!.sets.last!
        store.updateSet(workoutID: first.id, setID: amrap.id) { $0.reps = 8 }
        let summary = store.completeWorkout(first.id, now: now.addingTimeInterval(45 * 60))!
        #expect(summary.completedSets == 6)
        #expect(summary.totalSets == 6)
        #expect(summary.amrapReps == 8)
        #expect(summary.amrapTarget == 5)
        #expect(summary.estimatedOneRepMax == 107.644)
        #expect(summary.duration == 45 * 60)
        #expect(summary.streak == 1)
        #expect(summary.completedCycle == nil)
        #expect(!summary.missedRepTarget)
    }

    @Test func finishingCycleReportsNextTrainingMax() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(advanceMode: .perWorkout), now: now)
        var last: CompletionSummary?
        for workout in store.plannedWorkouts(programID: program.id).prefix(4) {
            store.startWorkout(workout.id, now: now)
            last = store.completeWorkout(workout.id, now: now)
        }
        #expect(last?.completedCycle == 0)
        #expect(last?.nextTrainingMax == 105)
        #expect(store.currentHeader(programID: program.id)?.trainingMax == 105)
    }

    @Test func accessoriesPrefillFromLastTime() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: now)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: now)
        let accessoryID = store.addAccessory(to: planned[0].id, named: "  Leg Press ")!
        let sets = store.workout(planned[0].id)!.accessories[0].sets
        #expect(sets.count == 3)
        store.updateAccessorySet(workoutID: planned[0].id, accessoryID: accessoryID, setID: sets[0].id) { $0.weight = 100; $0.reps = 12 }
        store.updateAccessorySet(workoutID: planned[0].id, accessoryID: accessoryID, setID: sets[1].id) { $0.weight = 100; $0.reps = 10 }
        store.updateAccessorySet(workoutID: planned[0].id, accessoryID: accessoryID, setID: sets[2].id) { $0.weight = 100; $0.reps = 8 }
        store.addAccessorySet(workoutID: planned[0].id, accessoryID: accessoryID)
        #expect(store.workout(planned[0].id)!.accessories[0].sets.map(\.reps) == [12, 10, 8, 8])
        store.completeWorkout(planned[0].id, now: now)

        store.startWorkout(planned[1].id, now: now)
        store.addAccessory(to: planned[1].id, named: "leg press")
        let prefilled = store.workout(planned[1].id)!.accessories[0]
        #expect(prefilled.name == "Leg Press")
        #expect(prefilled.sets.map(\.reps) == [12, 10, 8, 8])
        #expect(prefilled.sets.allSatisfy { $0.weight == 100 && !$0.isCompleted })
        #expect(store.recentAccessoryNames() == ["Leg Press"])
    }

    @Test func persistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WorkoutStore(fileURL: url, calendar: TestCalendar.calendar)
        let program = store.createProgram(makeProgram(), now: now)
        store.startWorkout(store.plannedWorkouts(programID: program.id)[0].id, now: now)
        store.saveNow()

        let reloaded = WorkoutStore(fileURL: url, calendar: TestCalendar.calendar)
        #expect(reloaded.programs == store.programs)
        #expect(reloaded.workouts == store.workouts)
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
struct StreakTests {
    let monday = TestCalendar.date("2026-09-28", hour: 10)

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

        // Friday's workout is never done; by Sunday it counts as missed.
        store.refresh(now: TestCalendar.date("2026-10-04", hour: 9))
        #expect(store.streak() == StreakSummary(current: 0, best: 2))
    }

    @Test func reschedulingInTimeProtectsStreak() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: monday)
        store.completeWorkout(planned[0].id, now: monday)

        // Wednesday's workout is pushed to Thursday on Wednesday, then done Thursday.
        let wednesday = TestCalendar.date("2026-09-30", hour: 8)
        store.reschedule(workoutID: planned[1].id, to: TestCalendar.date("2026-10-01"), scope: .onlyThis, now: wednesday)
        let thursday = TestCalendar.date("2026-10-01", hour: 18)
        store.refresh(now: thursday)
        store.startWorkout(planned[1].id, now: thursday)
        store.completeWorkout(planned[1].id, now: thursday)
        #expect(store.streak().current == 2)
    }

    @Test func skipRules() {
        let store = makeStore()
        let program = store.createProgram(makeProgram(), now: monday)
        let planned = store.plannedWorkouts(programID: program.id)
        store.startWorkout(planned[0].id, now: monday)
        store.completeWorkout(planned[0].id, now: monday)

        // Skipping ahead of time is re-planning.
        store.skipWorkout(planned[2].id, now: monday)
        #expect(store.streak().current == 1)

        // Skipping on the day breaks the streak.
        let wednesday = TestCalendar.date("2026-09-30", hour: 12)
        store.skipWorkout(planned[1].id, now: wednesday)
        #expect(store.streak().current == 0)
        #expect(store.streak().best == 1)
    }

    @Test func lateCompletionRestartsStreak() {
        let events = StreakCalculator.summary(for: [
            Workout(programID: UUID(), sessionIndex: 0, scheduledDate: TestCalendar.date("2026-09-28"), status: .completed,
                    completedAt: TestCalendar.date("2026-09-28", hour: 9)),
            Workout(programID: UUID(), sessionIndex: 1, scheduledDate: TestCalendar.date("2026-09-30"), status: .completed,
                    completedAt: TestCalendar.date("2026-10-03", hour: 9), missedOn: TestCalendar.date("2026-09-30")),
        ])
        #expect(events == StreakSummary(current: 1, best: 1))
    }
}
