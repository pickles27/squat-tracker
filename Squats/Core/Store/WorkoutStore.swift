import Foundation
import Observation

/// How a workout should look in lists and the calendar.
enum DisplayStatus: String, Sendable {
    case upcoming, today, overdue, missed, inProgress, completed, skipped
}

struct LiftResult: Hashable, Identifiable, Sendable {
    var liftID: String
    var liftName: String
    var trainingMax: Double
    var amrapWeight: Double?
    var amrapReps: Int?
    var amrapTarget: Int?
    var amrapMax: Int?
    var estimatedOneRepMax: Double?
    var previousBestOneRepMax: Double?
    /// Completed sets where fewer reps than expected were done.
    var missedSets: Int

    var id: String { liftID }

    var isPersonalRecord: Bool {
        guard let estimate = estimatedOneRepMax, let previous = previousBestOneRepMax else { return false }
        return estimate > previous
    }
}

struct LiftTrainingMax: Hashable, Identifiable, Sendable {
    var liftID: String
    var liftName: String
    var trainingMax: Double
    var id: String { liftID }
}

struct CompletionSummary: Identifiable, Hashable, Sendable {
    var workoutID: UUID
    var programID: UUID
    var title: String
    var subtitle: String
    var unit: WeightUnit
    var duration: TimeInterval
    var completedSets: Int
    var totalSets: Int
    var volume: Double
    var accessorySets: Int
    var lifts: [LiftResult]
    var isTestWeek: Bool
    /// Set when this workout finished a cycle; `nextTrainingMaxes` then holds the new maxes.
    var completedCycle: Int?
    var nextTrainingMaxes: [LiftTrainingMax]
    var suggestions: [TrainingMaxSuggestion]
    var streak: Int

    var id: UUID { workoutID }
}

/// Single source of truth for one signed-in user's data, persisted as JSON and synced as a whole file.
@MainActor
@Observable
final class WorkoutStore {
    private(set) var programs: [Program] = []
    private(set) var workouts: [Workout] = []
    private(set) var exercises: [Exercise] = []
    private(set) var deletions: [Tombstone] = []
    var lastError: String?

    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let fileURL: URL?
    /// How far ahead the calendar is filled with planned workouts.
    @ObservationIgnored var horizonDays = 84
    /// Source of `updatedAt` stamps (injectable for tests).
    @ObservationIgnored var clock: () -> Date = { Date() }
    /// Called after every save that came from a local change (used to trigger sync uploads).
    @ObservationIgnored var onDidSave: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Days after the scheduled day before an untouched workout counts as missed.
    static let missGraceDays = 1

    init(fileURL: URL?, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if let fileURL { load(from: fileURL) }
        ensureBuiltInExercises()
    }

    // MARK: - Persistence & sync

    private func load(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: url))
            programs = data.programs
            workouts = data.workouts
            exercises = data.exercises
            deletions = data.deletions
        } catch {
            // Never overwrite data we couldn't read; keep it aside so it can be recovered.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            lastError = "Saved data couldn't be read, so it was set aside as \(backup.lastPathComponent)."
        }
    }

    func snapshot() -> AppData {
        AppData(programs: programs, workouts: workouts, exercises: exercises, deletions: deletions)
    }

    static func encode(_ data: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(data)
    }

    /// Replaces everything with merged data (e.g. from `SyncMerge`) and saves without triggering `onDidSave`.
    func replaceAll(with data: AppData, now: Date = .now) {
        let programIDs = Set(data.programs.map(\.id))
        programs = data.programs
        workouts = data.workouts.filter { programIDs.contains($0.programID) }
        exercises = data.exercises
        deletions = data.deletions
        ensureBuiltInExercises()
        markMissed(now: now)
        for program in programs where !program.isArchived {
            topUp(programID: program.id, now: now)
            renumber(programID: program.id)
        }
        persist(notify: false)
    }

    func saveNow() {
        persist(notify: true)
    }

    private func persist(notify: Bool) {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else {
            if notify { onDidSave?() }
            return
        }
        do {
            let data = try Self.encode(snapshot())
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            if notify { onDidSave?() }
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func setNeedsSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func recordDeletion(_ ids: [UUID]) {
        let now = clock()
        deletions.append(contentsOf: ids.map { Tombstone(id: $0, deletedAt: now) })
    }

    // MARK: - Lookup

    func program(_ id: UUID?) -> Program? {
        guard let id else { return nil }
        return programs.first { $0.id == id }
    }

    func workout(_ id: UUID?) -> Workout? {
        guard let id else { return nil }
        return workouts.first { $0.id == id }
    }

    private func programIndex(_ id: UUID) -> Int? {
        programs.firstIndex { $0.id == id }
    }

    var activePrograms: [Program] {
        programs.filter { !$0.isArchived }.sorted { $0.createdAt < $1.createdAt }
    }

    var archivedPrograms: [Program] {
        programs.filter(\.isArchived).sorted { $0.createdAt > $1.createdAt }
    }

    func workouts(programID: UUID) -> [Workout] {
        workouts.filter { $0.programID == programID }
    }

    static func scheduleOrder(_ lhs: Workout, _ rhs: Workout) -> Bool {
        (lhs.scheduledDate, lhs.sessionIndex) < (rhs.scheduledDate, rhs.sessionIndex)
    }

    var inProgressWorkouts: [Workout] {
        workouts.filter { $0.status == .inProgress }
            .sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    func plannedWorkouts(programID: UUID? = nil) -> [Workout] {
        workouts.filter { $0.status == .planned && (programID == nil || $0.programID == programID) }
            .sorted(by: Self.scheduleOrder)
    }

    /// The program's next planned workout. Only this one should be offered "Start early".
    func nextWorkout(programID: UUID) -> Workout? {
        plannedWorkouts(programID: programID).first
    }

    /// What to show as "today's workout": one in progress, else the next planned one due today or overdue.
    /// Nil means today is a rest day for this program.
    func currentWorkout(programID: UUID, now: Date = .now) -> Workout? {
        if let active = inProgressWorkouts.first(where: { $0.programID == programID }) { return active }
        let today = calendar.startOfDay(for: now)
        return plannedWorkouts(programID: programID).first { $0.scheduledDate <= today }
    }

    /// The next planned workout of every active program, soonest first.
    func upNext() -> [Workout] {
        activePrograms.compactMap { nextWorkout(programID: $0.id) }.sorted(by: Self.scheduleOrder)
    }

    /// Completed and skipped workouts, most recent first.
    func history(programID: UUID? = nil) -> [Workout] {
        workouts.filter { ($0.status == .completed || $0.status == .skipped) && (programID == nil || $0.programID == programID) }
            .sorted { displayDate(of: $0) > displayDate(of: $1) }
    }

    /// Started workouts show on the day they were actually done.
    func displayDate(of workout: Workout) -> Date {
        switch workout.status {
        case .inProgress, .completed: workout.startedAt ?? workout.scheduledDate
        case .planned, .skipped: workout.scheduledDate
        }
    }

    func workoutsByDay(programID: UUID? = nil) -> [Date: [Workout]] {
        let relevant = programID.map { id in workouts.filter { $0.programID == id } } ?? workouts
        return Dictionary(grouping: relevant) { calendar.startOfDay(for: displayDate(of: $0)) }
    }

    func displayStatus(of workout: Workout, now: Date = .now) -> DisplayStatus {
        switch workout.status {
        case .inProgress: return .inProgress
        case .completed: return .completed
        case .skipped: return .skipped
        case .planned:
            let today = calendar.startOfDay(for: now)
            if workout.scheduledDate < today { return workout.missedOn == nil ? .overdue : .missed }
            return workout.scheduledDate == today ? .today : .upcoming
        }
    }

    /// Planned workouts whose day has passed but that can still be done or moved without breaking the streak.
    func workoutsAtRisk(now: Date = .now) -> [Workout] {
        plannedWorkouts().filter { displayStatus(of: $0, now: now) == .overdue }
    }

    func header(for workout: Workout) -> SessionHeader? {
        workout.header ?? prescription(for: workout)?.header
    }

    /// Planned workouts are computed from the program; started ones return what was frozen at start.
    func prescription(for workout: Workout) -> SessionPrescription? {
        if workout.status == .planned || (workout.header == nil && workout.sets.isEmpty) {
            guard let program = program(workout.programID) else { return nil }
            return ProgramEngine.prescription(for: program, session: workout.sessionIndex)
        }
        guard let header = workout.header else { return nil }
        let sets = workout.sets.map {
            PrescribedSet(liftID: $0.liftID, liftName: $0.liftName, kind: $0.kind, weight: $0.targetWeight,
                          reps: $0.targetReps, isAMRAP: $0.isAMRAP, maxReps: $0.maxReps, percentOfTM: $0.percentOfTM)
        }
        return SessionPrescription(header: header, sets: sets)
    }

    /// Where the program is now: the next planned session, or the last one started.
    func currentHeader(programID: UUID) -> SessionHeader? {
        if let next = nextWorkout(programID: programID) { return header(for: next) }
        return workouts(programID: programID)
            .filter(\.isStarted)
            .max { $0.sessionIndex < $1.sessionIndex }
            .flatMap(header(for:))
    }

    func currentProgramWeek(programID: UUID) -> Int {
        if let next = nextWorkout(programID: programID), let header = header(for: next) { return header.programWeek }
        let started = workouts(programID: programID).filter(\.isStarted).compactMap(\.header?.programWeek)
        return (started.max() ?? -1) + 1
    }

    /// Each lift's training max at the program's current week.
    func trainingMaxes(programID: UUID) -> [LiftTrainingMax] {
        guard let program = program(programID) else { return [] }
        let week = currentProgramWeek(programID: programID)
        return program.lifts.map {
            LiftTrainingMax(liftID: $0.id, liftName: $0.name,
                            trainingMax: ProgramEngine.trainingMax(liftID: $0.id, programWeek: week, program: program))
        }
    }

    func streak(programID: UUID? = nil) -> StreakSummary {
        StreakCalculator.summary(for: programID.map(workouts(programID:)) ?? workouts)
    }

    static func estimatedOneRepMax(of workout: Workout, liftID: String) -> Double? {
        guard let set = workout.sets.last(where: { $0.liftID == liftID && $0.kind == .main && $0.isAMRAP && $0.isCompleted }),
              set.reps > 0 else { return nil }
        return StrengthMath.estimatedOneRepMax(weight: set.weight, reps: set.reps)
    }

    /// Best estimated 1RM for a lift across all programs in the same unit.
    func bestEstimatedOneRepMax(liftID: String, unit: WeightUnit, excluding workoutID: UUID? = nil) -> Double? {
        let programIDs = Set(programs.filter { $0.unit == unit }.map(\.id))
        return workouts
            .filter { $0.status == .completed && $0.id != workoutID && programIDs.contains($0.programID) }
            .compactMap { Self.estimatedOneRepMax(of: $0, liftID: liftID) }
            .max()
    }

    // MARK: - Exercise library

    var visibleExercises: [Exercise] {
        exercises.filter { !$0.isHidden }.sorted {
            ($0.category.sortIndex, $0.name.lowercased()) < ($1.category.sortIndex, $1.name.lowercased())
        }
    }

    var hiddenBuiltInExercises: [Exercise] {
        exercises.filter { $0.isBuiltIn && $0.isHidden }.sorted { $0.name < $1.name }
    }

    func exercise(named name: String) -> Exercise? {
        let key = name.lowercased()
        return exercises.first { $0.name.lowercased() == key }
    }

    private var startedWorkoutsNewestFirst: [Workout] {
        workouts.filter(\.isStarted).sorted { ($0.startedAt ?? $0.scheduledDate) > ($1.startedAt ?? $1.scheduledDate) }
    }

    func usageCount(ofExerciseNamed name: String) -> Int {
        let key = name.lowercased()
        return workouts.filter(\.isStarted).reduce(0) { total, workout in
            total + workout.accessories.filter { $0.name.lowercased() == key }.count
        }
    }

    /// Your most-logged accessories (most used first, then most recent). Empty until you've logged some.
    func quickAddExercises(limit: Int = 8) -> [Exercise] {
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        for workout in workouts where workout.isStarted {
            for accessory in workout.accessories {
                let key = accessory.name.lowercased()
                counts[key, default: 0] += 1
                lastUsed[key] = max(lastUsed[key] ?? .distantPast, workout.startedAt ?? workout.scheduledDate)
            }
        }
        return visibleExercises
            .filter { counts[$0.name.lowercased(), default: 0] > 0 }
            .sorted {
                let lhs = $0.name.lowercased(), rhs = $1.name.lowercased()
                if counts[lhs] != counts[rhs] { return counts[lhs, default: 0] > counts[rhs, default: 0] }
                return (lastUsed[lhs] ?? .distantPast) > (lastUsed[rhs] ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    func lastAccessory(named name: String, excluding workoutID: UUID? = nil) -> AccessoryExercise? {
        let key = name.lowercased()
        return startedWorkoutsNewestFirst
            .lazy
            .filter { $0.id != workoutID }
            .compactMap { $0.accessories.last { $0.name.lowercased() == key } }
            .first
    }

    /// Adds an exercise to the library (un-hiding it if it already exists).
    @discardableResult
    func addExercise(named rawName: String, category: ExerciseCategory) -> Exercise? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let index = exercises.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            exercises[index].isHidden = false
            exercises[index].category = category
            exercises[index].updatedAt = clock()
            setNeedsSave()
            return exercises[index]
        }
        let exercise = Exercise(id: UUID(), name: name, category: category, isBuiltIn: false, updatedAt: clock())
        exercises.append(exercise)
        setNeedsSave()
        return exercise
    }

    func updateExercise(_ id: UUID, _ body: (inout Exercise) -> Void) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        body(&exercises[index])
        exercises[index].updatedAt = clock()
        setNeedsSave()
    }

    /// Built-ins are hidden (restorable); your own exercises are deleted. Past workouts keep their logs.
    func removeExercise(_ id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        if exercises[index].isBuiltIn {
            exercises[index].isHidden = true
            exercises[index].updatedAt = clock()
        } else {
            exercises.remove(at: index)
            recordDeletion([id])
        }
        setNeedsSave()
    }

    func restoreBuiltInExercises() {
        for index in exercises.indices where exercises[index].isBuiltIn && exercises[index].isHidden {
            exercises[index].isHidden = false
            exercises[index].updatedAt = clock()
        }
        setNeedsSave()
    }

    private func ensureBuiltInExercises() {
        let existing = Set(exercises.map(\.id))
        exercises.append(contentsOf: ExerciseCatalog.builtIns.filter { !existing.contains($0.id) })
    }

    // MARK: - Programs

    @discardableResult
    func createProgram(_ program: Program, now: Date = .now) -> Program {
        var program = program
        program.startDate = calendar.startOfDay(for: program.startDate)
        program.generatedThrough = nil
        program.updatedAt = clock()
        programs.append(program)
        normalize(programID: program.id, now: now)
        return program
    }

    /// For name, color and rounding. Use the schedule functions for days and dates.
    func updateProgram(_ id: UUID, _ body: (inout Program) -> Void) {
        guard let index = programIndex(id) else { return }
        body(&programs[index])
        programs[index].updatedAt = clock()
        setNeedsSave()
    }

    func deleteProgram(_ id: UUID) {
        let removed = workouts.filter { $0.programID == id }.map(\.id)
        programs.removeAll { $0.id == id }
        workouts.removeAll { $0.programID == id }
        recordDeletion([id] + removed)
        setNeedsSave()
    }

    /// Ends a program: keeps its history, drops its future plan.
    func archiveProgram(_ id: UUID) {
        guard let index = programIndex(id) else { return }
        programs[index].isArchived = true
        programs[index].updatedAt = clock()
        let removed = workouts.filter { $0.programID == id && $0.status == .planned }.map(\.id)
        workouts.removeAll { removed.contains($0.id) }
        recordDeletion(removed)
        setNeedsSave()
    }

    func restoreProgram(_ id: UUID, now: Date = .now) {
        guard let index = programIndex(id) else { return }
        programs[index].isArchived = false
        programs[index].generatedThrough = nil
        programs[index].updatedAt = clock()
        normalize(programID: id, now: now)
    }

    /// Sets a lift's training max from `fromProgramWeek` (default: the current week) onward;
    /// later cycles keep adding the lift's increment.
    func adjustTrainingMax(programID: UUID, liftID: String, to value: Double, fromProgramWeek: Int? = nil,
                           reason: String? = nil, now: Date = .now) {
        guard value > 0, let index = programIndex(programID) else { return }
        let week = fromProgramWeek ?? currentProgramWeek(programID: programID)
        programs[index].trainingMaxAdjustments.removeAll { $0.liftID == liftID && $0.fromProgramWeek >= week }
        programs[index].trainingMaxAdjustments.append(
            TrainingMaxAdjustment(liftID: liftID, fromProgramWeek: week, trainingMax: value, date: now, reason: reason)
        )
        programs[index].updatedAt = clock()
        setNeedsSave()
    }

    func apply(_ suggestion: TrainingMaxSuggestion, programID: UUID, now: Date = .now) {
        adjustTrainingMax(programID: programID, liftID: suggestion.liftID, to: suggestion.suggestedTrainingMax,
                          fromProgramWeek: suggestion.fromProgramWeek, reason: suggestion.explanation, now: now)
    }

    /// Changes which weekdays you train (the count is fixed by the program) and re-plans upcoming
    /// workouts onto them in order, starting today.
    func updateWeekdays(programID: UUID, to weekdays: Set<Int>, now: Date = .now) {
        guard let index = programIndex(programID), weekdays.count == programs[index].schedule.sessionsPerWeek else { return }
        programs[index].schedule.weekdays = weekdays
        programs[index].updatedAt = clock()
        let anchor = max(calendar.startOfDay(for: now), calendar.startOfDay(for: programs[index].startDate))
        var day = ScheduleMath.nextDate(onOrAfter: anchor, weekdays: weekdays, calendar)
        var plan: [UUID: Date] = [:]
        for (offset, workout) in plannedWorkouts(programID: programID).enumerated() {
            if offset > 0 { day = ScheduleMath.nextDate(after: day, weekdays: weekdays, calendar) }
            plan[workout.id] = day
        }
        apply(plan)
        programs[index].generatedThrough = plan.values.max() ?? ScheduleMath.addingDays(-1, to: anchor, calendar)
        normalize(programID: programID, now: now)
    }

    // MARK: - Moving workouts

    /// New dates for every workout a move would touch: just this one, or this one and every later
    /// planned workout moved by the same number of days.
    func planReschedule(workoutID: UUID, to newDate: Date, shiftFollowing: Bool) -> [UUID: Date] {
        guard let workout = workout(workoutID), workout.status == .planned else { return [:] }
        let target = calendar.startOfDay(for: newDate)
        guard shiftFollowing else { return [workout.id: target] }
        let delta = ScheduleMath.days(from: workout.scheduledDate, to: target, calendar)
        let following = plannedWorkouts(programID: workout.programID).filter { !Self.scheduleOrder($0, workout) }
        return Dictionary(uniqueKeysWithValues: following.map {
            ($0.id, ScheduleMath.addingDays(delta, to: $0.scheduledDate, calendar))
        })
    }

    func reschedule(workoutID: UUID, to newDate: Date, shiftFollowing: Bool, now: Date = .now) {
        guard let workout = workout(workoutID), let index = programIndex(workout.programID) else { return }
        let plan = planReschedule(workoutID: workoutID, to: newDate, shiftFollowing: shiftFollowing)
        guard !plan.isEmpty else { return }
        apply(plan)
        if shiftFollowing {
            shiftSchedulePattern(programIndex: index, by: ScheduleMath.days(from: workout.scheduledDate, to: newDate, calendar))
        }
        normalize(programID: workout.programID, now: now)
    }

    /// "Rest another day": the workout moves to tomorrow (or the day after today, if it's overdue).
    func restAnotherDay(workoutID: UUID, shiftFollowing: Bool, now: Date = .now) {
        guard let workout = workout(workoutID), workout.status == .planned else { return }
        let base = max(workout.scheduledDate, calendar.startOfDay(for: now))
        reschedule(workoutID: workoutID, to: ScheduleMath.addingDays(1, to: base, calendar), shiftFollowing: shiftFollowing, now: now)
    }

    /// Moves a future workout to today and starts it, optionally pulling later workouts forward too.
    func startEarly(workoutID: UUID, shiftFollowing: Bool, now: Date = .now) {
        guard let workout = workout(workoutID), workout.status == .planned else { return }
        let today = calendar.startOfDay(for: now)
        if workout.scheduledDate > today {
            reschedule(workoutID: workoutID, to: today, shiftFollowing: shiftFollowing, now: now)
        }
        startWorkout(workoutID, now: now)
    }

    func planShift(programID: UUID, days: Int) -> [UUID: Date] {
        Dictionary(uniqueKeysWithValues: plannedWorkouts(programID: programID).map {
            ($0.id, ScheduleMath.addingDays(days, to: $0.scheduledDate, calendar))
        })
    }

    /// Moves every planned workout of the program later (positive) or earlier (negative) by `days`.
    func shiftProgram(programID: UUID, days: Int, now: Date = .now) {
        guard days != 0, let index = programIndex(programID) else { return }
        apply(planShift(programID: programID, days: days))
        shiftSchedulePattern(programIndex: index, by: days)
        normalize(programID: programID, now: now)
    }

    /// After a bulk shift the new days stick: the generation window and saved weekdays move with it.
    private func shiftSchedulePattern(programIndex index: Int, by days: Int) {
        guard days != 0 else { return }
        if let through = programs[index].generatedThrough {
            programs[index].generatedThrough = ScheduleMath.addingDays(days, to: through, calendar)
        }
        programs[index].schedule = programs[index].schedule.rotated(byDays: days)
        programs[index].updatedAt = clock()
    }

    private func apply(_ plan: [UUID: Date]) {
        guard !plan.isEmpty else { return }
        let stamp = clock()
        for index in workouts.indices {
            if let date = plan[workouts[index].id], workouts[index].scheduledDate != date {
                workouts[index].scheduledDate = date
                workouts[index].updatedAt = stamp
            }
        }
    }

    // MARK: - Schedule maintenance

    /// Marks missed workouts, keeps the calendar filled ahead, and re-sequences planned sessions.
    /// Cheap and idempotent; call on launch and whenever the app becomes active.
    func refresh(now: Date = .now) {
        var changed = markMissed(now: now)
        for program in programs where !program.isArchived {
            changed = topUp(programID: program.id, now: now) || changed
            changed = renumber(programID: program.id) || changed
        }
        if changed { setNeedsSave() }
    }

    private func normalize(programID: UUID, now: Date) {
        markMissed(now: now)
        topUp(programID: programID, now: now)
        renumber(programID: programID)
        setNeedsSave()
    }

    @discardableResult
    private func markMissed(now: Date) -> Bool {
        let cutoff = ScheduleMath.addingDays(-Self.missGraceDays, to: now, calendar)
        var changed = false
        for index in workouts.indices
        where workouts[index].status == .planned && workouts[index].missedOn == nil && workouts[index].scheduledDate < cutoff {
            workouts[index].missedOn = workouts[index].scheduledDate
            workouts[index].updatedAt = clock()
            changed = true
        }
        return changed
    }

    /// Generates planned workouts on the program's days up to the horizon. IDs are derived from the
    /// program and a running count so two devices generating the same slots produce the same records.
    @discardableResult
    private func topUp(programID: UUID, now: Date) -> Bool {
        guard let index = programIndex(programID) else { return false }
        let program = programs[index]
        guard program.schedule.isValid, program.template.isValid, !program.isArchived else { return false }
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: program.startDate)
        let horizonEnd = ScheduleMath.addingDays(horizonDays, to: max(today, start), calendar)
        let from = program.generatedThrough.map { max(ScheduleMath.addingDays(1, to: $0, calendar), today) } ?? max(start, today)
        guard from <= horizonEnd else { return false }

        let dates = ScheduleMath.dates(from: from, through: horizonEnd, weekdays: program.schedule.weekdays, calendar)
        let existing = workouts(programID: programID)
        var nextIndex = (existing.map(\.sessionIndex).max() ?? -1) + 1
        var ordinal = existing.count + deletions.count
        let stamp = clock()
        for date in dates {
            var id = StableID.uuid("\(programID.uuidString)|generated|\(ordinal)")
            while workouts.contains(where: { $0.id == id }) {
                ordinal += 1
                id = StableID.uuid("\(programID.uuidString)|generated|\(ordinal)")
            }
            workouts.append(Workout(id: id, programID: programID, sessionIndex: nextIndex, scheduledDate: date, updatedAt: stamp))
            nextIndex += 1
            ordinal += 1
        }
        programs[index].generatedThrough = horizonEnd
        return true
    }

    /// Planned workouts take the free session slots in date order, so the next workout you do is always
    /// the next step of the program. Started workouts keep their slot; skipped ones give theirs up.
    @discardableResult
    private func renumber(programID: UUID) -> Bool {
        let indices = workouts.indices.filter { workouts[$0].programID == programID && workouts[$0].status != .skipped }
        let taken = Set(indices.filter { workouts[$0].isStarted }.map { workouts[$0].sessionIndex })
        let planned = indices
            .filter { workouts[$0].status == .planned }
            .sorted { Self.scheduleOrder(workouts[$0], workouts[$1]) }
        var next = 0
        var changed = false
        for index in planned {
            while taken.contains(next) { next += 1 }
            if workouts[index].sessionIndex != next {
                workouts[index].sessionIndex = next
                changed = true
            }
            next += 1
        }
        return changed
    }

    // MARK: - Workout lifecycle

    private func mutateWorkout(_ id: UUID, _ body: (inout Workout) -> Void) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { return }
        body(&workouts[index])
        workouts[index].updatedAt = clock()
        setNeedsSave()
    }

    /// Freezes the prescription into real sets (actual = expected until edited) and starts the clock.
    func startWorkout(_ id: UUID, now: Date = .now) {
        guard let workout = workout(id), workout.status == .planned,
              let prescription = prescription(for: workout) else { return }
        mutateWorkout(id) {
            $0.status = .inProgress
            $0.startedAt = now
            $0.header = prescription.header
            $0.sets = prescription.sets.map {
                WorkoutSet(liftID: $0.liftID, liftName: $0.liftName, kind: $0.kind, targetWeight: $0.weight,
                           targetReps: $0.reps, isAMRAP: $0.isAMRAP, maxReps: $0.maxReps, percentOfTM: $0.percentOfTM,
                           weight: $0.weight, reps: $0.reps)
            }
        }
        renumber(programID: workout.programID)
    }

    @discardableResult
    func completeWorkout(_ id: UUID, now: Date = .now) -> CompletionSummary? {
        guard let workout = workout(id), workout.status == .inProgress, let program = program(workout.programID) else {
            return nil
        }
        mutateWorkout(id) {
            $0.status = .completed
            $0.completedAt = now
        }
        saveNow()

        let header = workout.header ?? prescription(for: workout)?.header
        let done = workout.sets.filter(\.isCompleted)
        var liftIDs: [String] = []
        for set in workout.sets where !liftIDs.contains(set.liftID) { liftIDs.append(set.liftID) }

        let lifts = liftIDs.map { liftID -> LiftResult in
            let sets = workout.sets.filter { $0.liftID == liftID }
            let amrap = sets.last { $0.kind == .main && $0.isAMRAP }
            return LiftResult(
                liftID: liftID,
                liftName: sets.first?.liftName ?? liftID,
                trainingMax: header?.trainingMaxes[liftID] ?? 0,
                amrapWeight: amrap?.weight,
                amrapReps: amrap.flatMap { $0.isCompleted ? $0.reps : nil },
                amrapTarget: amrap?.targetReps,
                amrapMax: amrap?.maxReps,
                estimatedOneRepMax: Self.estimatedOneRepMax(of: workout, liftID: liftID),
                previousBestOneRepMax: bestEstimatedOneRepMax(liftID: liftID, unit: program.unit, excluding: id),
                missedSets: sets.filter(\.missedTarget).count
            )
        }

        var completedCycle: Int?
        var nextMaxes: [LiftTrainingMax] = []
        var suggestions: [TrainingMaxSuggestion] = []
        if let header {
            if ProgramEngine.completesCycle(header, template: program.template), let cycle = header.cycle {
                completedCycle = cycle
                nextMaxes = program.lifts.map {
                    LiftTrainingMax(liftID: $0.id, liftName: $0.name,
                                    trainingMax: ProgramEngine.trainingMax(liftID: $0.id, programWeek: header.programWeek + 1, program: program))
                }
                suggestions += stallSuggestions(program: program, cycle: cycle, header: header)
            }
            if header.weekKind == .test {
                suggestions += testSuggestions(program: program, workout: workout, header: header)
            }
        }

        return CompletionSummary(
            workoutID: id,
            programID: program.id,
            title: header?.title ?? program.name,
            subtitle: header?.subtitle ?? "",
            unit: program.unit,
            duration: now.timeIntervalSince(workout.startedAt ?? now),
            completedSets: done.count,
            totalSets: workout.sets.count,
            volume: done.reduce(0) { $0 + $1.weight * Double($1.reps) },
            accessorySets: workout.accessories.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count },
            lifts: lifts,
            isTestWeek: header?.weekKind == .test,
            completedCycle: completedCycle,
            nextTrainingMaxes: nextMaxes,
            suggestions: suggestions,
            streak: streak().current
        )
    }

    /// 5/3/1 guideline: if a lift misses its reps for a whole cycle, drop its TM by three increments.
    private func stallSuggestions(program: Program, cycle: Int, header: SessionHeader) -> [TrainingMaxSuggestion] {
        let cycleWorkouts = workouts(programID: program.id).filter { $0.status == .completed && $0.header?.cycle == cycle }
        return program.lifts.compactMap { lift in
            let amrapSets = cycleWorkouts.flatMap { $0.sets.filter { $0.liftID == lift.id && $0.kind == .main && $0.isAMRAP } }
            guard amrapSets.count >= 2, amrapSets.allSatisfy({ !$0.isCompleted || $0.reps < $0.targetReps }) else { return nil }
            let current = ProgramEngine.trainingMax(liftID: lift.id, programWeek: header.programWeek, program: program)
            let suggested = max(0, current - 3 * lift.increment)
            return TrainingMaxSuggestion(
                liftID: lift.id, liftName: lift.name, reason: .stalled,
                currentTrainingMax: current, suggestedTrainingMax: suggested, fromProgramWeek: header.programWeek + 1,
                explanation: "You missed the rep target on every \(lift.name) AMRAP set this cycle. The 5/3/1 guideline is to drop the training max by three increments."
            )
        }
    }

    /// TM test: fewer than 3 reps at 100% means reset the TM to 90% of the 1RM estimated from that set.
    private func testSuggestions(program: Program, workout: Workout, header: SessionHeader) -> [TrainingMaxSuggestion] {
        program.lifts.compactMap { lift in
            guard let set = workout.sets.last(where: { $0.liftID == lift.id && $0.kind == .main && $0.isAMRAP }),
                  set.isCompleted, set.reps < set.targetReps else { return nil }
            let current = header.trainingMaxes[lift.id] ?? set.targetWeight
            let suggested = set.reps > 0
                ? StrengthMath.round(StrengthMath.estimatedOneRepMax(weight: set.weight, reps: set.reps) * program.template.trainingMaxPercent,
                                     to: program.rounding)
                : max(0, current - 3 * lift.increment)
            guard suggested < current else { return nil }
            return TrainingMaxSuggestion(
                liftID: lift.id, liftName: lift.name, reason: .failedTest,
                currentTrainingMax: current, suggestedTrainingMax: suggested, fromProgramWeek: header.programWeek + 1,
                explanation: "You got \(set.reps) of the 3 reps needed at your \(lift.name) training max. Reset it from this set for the next cycle."
            )
        }
    }

    /// Throws away everything logged and puts the workout back on the plan.
    func discardWorkout(_ id: UUID) {
        guard let workout = workout(id), workout.status == .inProgress else { return }
        mutateWorkout(id) {
            $0.status = .planned
            $0.startedAt = nil
            $0.header = nil
            $0.sets = []
            $0.accessories = []
            $0.notes = ""
            $0.lastSetCompletedAt = nil
        }
        renumber(programID: workout.programID)
    }

    /// Skipped days drop out of the sequence; the program carries on from the same step.
    func skipWorkout(_ id: UUID, now: Date = .now) {
        guard let workout = workout(id), workout.status == .planned else { return }
        let header = prescription(for: workout)?.header
        mutateWorkout(id) {
            $0.status = .skipped
            $0.skippedAt = now
            $0.header = header
        }
        normalize(programID: workout.programID, now: now)
    }

    func restoreSkippedWorkout(_ id: UUID, now: Date = .now) {
        guard let workout = workout(id), workout.status == .skipped else { return }
        mutateWorkout(id) {
            $0.status = .planned
            $0.skippedAt = nil
            $0.header = nil
        }
        normalize(programID: workout.programID, now: now)
    }

    /// Lets you fix a finished workout's log.
    func reopenWorkout(_ id: UUID) {
        guard let workout = workout(id), workout.status == .completed else { return }
        mutateWorkout(id) {
            $0.status = .inProgress
            $0.completedAt = nil
        }
    }

    func setNotes(_ notes: String, workoutID: UUID) {
        mutateWorkout(workoutID) { $0.notes = notes }
    }

    // MARK: - Sets

    func toggleSet(workoutID: UUID, setID: UUID, now: Date = .now) {
        mutateWorkout(workoutID) { workout in
            guard let index = workout.sets.firstIndex(where: { $0.id == setID }) else { return }
            workout.sets[index].isCompleted.toggle()
            workout.sets[index].completedAt = workout.sets[index].isCompleted ? now : nil
            if workout.sets[index].isCompleted { workout.lastSetCompletedAt = now }
        }
    }

    /// Edit actual weight/reps (or anything else) of a main-lift set.
    func updateSet(workoutID: UUID, setID: UUID, _ body: (inout WorkoutSet) -> Void) {
        mutateWorkout(workoutID) { workout in
            guard let index = workout.sets.firstIndex(where: { $0.id == setID }) else { return }
            body(&workout.sets[index])
        }
    }

    // MARK: - Accessories

    /// Adds an accessory to a workout. Expected and actual values are pre-filled from last time
    /// (otherwise 3 sets of 10 with no target). New names are added to the exercise library.
    @discardableResult
    func addAccessory(to workoutID: UUID, named rawName: String) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, workout(workoutID) != nil else { return nil }
        let previous = lastAccessory(named: name, excluding: workoutID)
        let sets = previous.map {
            $0.sets.map { AccessorySet(targetWeight: $0.weight, targetReps: $0.reps, weight: $0.weight, reps: $0.reps) }
        } ?? []
        let displayName = exercise(named: name)?.name ?? previous?.name ?? name
        if exercise(named: name) == nil { addExercise(named: name, category: .other) }
        let accessory = AccessoryExercise(
            name: displayName,
            sets: sets.isEmpty ? (0..<3).map { _ in AccessorySet(weight: 0, reps: 10) } : sets
        )
        mutateWorkout(workoutID) { $0.accessories.append(accessory) }
        return accessory.id
    }

    func removeAccessory(workoutID: UUID, accessoryID: UUID) {
        mutateWorkout(workoutID) { $0.accessories.removeAll { $0.id == accessoryID } }
    }

    func moveAccessories(workoutID: UUID, from source: IndexSet, to destination: Int) {
        mutateWorkout(workoutID) { workout in
            let moving = source.sorted().map { workout.accessories[$0] }
            let before = source.filter { $0 < destination }.count
            for index in source.sorted(by: >) { workout.accessories.remove(at: index) }
            workout.accessories.insert(contentsOf: moving, at: destination - before)
        }
    }

    private func mutateAccessory(workoutID: UUID, accessoryID: UUID, _ body: (inout AccessoryExercise, inout Workout) -> Void) {
        mutateWorkout(workoutID) { workout in
            guard let index = workout.accessories.firstIndex(where: { $0.id == accessoryID }) else { return }
            var accessory = workout.accessories[index]
            body(&accessory, &workout)
            workout.accessories[index] = accessory
        }
    }

    /// Adds a set copying the previous one, so a different rep count is one tap away.
    func addAccessorySet(workoutID: UUID, accessoryID: UUID) {
        mutateAccessory(workoutID: workoutID, accessoryID: accessoryID) { accessory, _ in
            let last = accessory.sets.last
            accessory.sets.append(AccessorySet(targetWeight: last?.targetWeight, targetReps: last?.targetReps,
                                               weight: last?.weight ?? 0, reps: last?.reps ?? 10))
        }
    }

    func removeAccessorySet(workoutID: UUID, accessoryID: UUID, setID: UUID) {
        mutateAccessory(workoutID: workoutID, accessoryID: accessoryID) { accessory, _ in
            accessory.sets.removeAll { $0.id == setID }
        }
    }

    /// Edit expected or actual weight/reps of an accessory set.
    func updateAccessorySet(workoutID: UUID, accessoryID: UUID, setID: UUID, _ body: (inout AccessorySet) -> Void) {
        mutateAccessory(workoutID: workoutID, accessoryID: accessoryID) { accessory, _ in
            guard let index = accessory.sets.firstIndex(where: { $0.id == setID }) else { return }
            body(&accessory.sets[index])
        }
    }

    func toggleAccessorySet(workoutID: UUID, accessoryID: UUID, setID: UUID, now: Date = .now) {
        mutateAccessory(workoutID: workoutID, accessoryID: accessoryID) { accessory, workout in
            guard let index = accessory.sets.firstIndex(where: { $0.id == setID }) else { return }
            accessory.sets[index].isCompleted.toggle()
            accessory.sets[index].completedAt = accessory.sets[index].isCompleted ? now : nil
            if accessory.sets[index].isCompleted { workout.lastSetCompletedAt = now }
        }
    }
}

extension ExerciseCategory {
    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
