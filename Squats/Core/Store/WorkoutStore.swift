import Foundation
import Observation

struct AppData: Codable, Sendable {
    var version = 1
    var programs: [Program] = []
    var workouts: [Workout] = []
}

enum FollowingStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Every following workout moves by the same number of days (like dragging a recurring event).
    case keepSpacing
    /// Following workouts are re-planned onto the program's workout days after the new date.
    case fitToSchedule

    var id: String { rawValue }

    var name: String {
        switch self {
        case .keepSpacing: "Shift by the same number of days"
        case .fitToSchedule: "Re-plan onto my workout days"
        }
    }
}

enum RescheduleScope: Hashable, Sendable {
    case onlyThis
    case thisAndFollowing(FollowingStyle)
}

/// How a workout should look in lists and the calendar.
enum DisplayStatus: String, Sendable {
    case upcoming, today, overdue, missed, inProgress, completed, skipped
}

struct CompletionSummary: Identifiable, Hashable, Sendable {
    var id: UUID { workoutID }
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
    var amrapWeight: Double?
    var amrapReps: Int?
    var amrapTarget: Int?
    var estimatedOneRepMax: Double?
    var previousBestOneRepMax: Double?
    var completedCycle: Int?
    var nextTrainingMax: Double?
    var streak: Int

    var isPersonalRecord: Bool {
        guard let estimate = estimatedOneRepMax, let previous = previousBestOneRepMax else { return false }
        return estimate > previous
    }

    var missedRepTarget: Bool {
        guard let reps = amrapReps, let target = amrapTarget else { return false }
        return reps < target
    }
}

/// Single source of truth for one signed-in user's programs and workouts, persisted as JSON.
@MainActor
@Observable
final class WorkoutStore {
    private(set) var programs: [Program] = []
    private(set) var workouts: [Workout] = []
    var lastError: String?

    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let fileURL: URL?
    /// How far ahead the calendar is filled with planned workouts.
    @ObservationIgnored var horizonDays = 84
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Days after the scheduled day before an untouched workout counts as missed.
    static let missGraceDays = 1

    init(fileURL: URL?, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if let fileURL { load(from: fileURL) }
    }

    // MARK: - Persistence

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func load(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(AppData.self, from: data)
            programs = decoded.programs
            workouts = decoded.workouts
        } catch {
            // Never overwrite data we couldn't read; keep it aside so it can be recovered.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            lastError = "Saved data couldn't be read, so it was set aside as \(backup.lastPathComponent)."
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        do {
            let data = try Self.makeEncoder().encode(AppData(programs: programs, workouts: workouts))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func setNeedsSave() {
        guard fileURL != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
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

    func nextWorkout(programID: UUID) -> Workout? {
        plannedWorkouts(programID: programID).first
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
        if let header = workout.header { return header }
        return prescription(for: workout)?.header
    }

    /// Planned workouts are computed from the program; started ones return what was frozen at start.
    func prescription(for workout: Workout) -> SessionPrescription? {
        if workout.status == .planned || (workout.header == nil && workout.sets.isEmpty) {
            guard let program = program(workout.programID) else { return nil }
            return ProgramEngine.prescription(for: program, sessionIndex: workout.sessionIndex)
        }
        guard let header = workout.header else { return nil }
        let sets = workout.sets.map {
            PrescribedSet(kind: $0.kind, weight: $0.targetWeight, reps: $0.targetReps, isAMRAP: $0.isAMRAP, percentOfTM: $0.percentOfTM)
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

    func streak(programID: UUID? = nil) -> StreakSummary {
        StreakCalculator.summary(for: programID.map(workouts(programID:)) ?? workouts)
    }

    func bestEstimatedOneRepMax(liftName: String, unit: WeightUnit, excluding workoutID: UUID? = nil) -> Double? {
        let programIDs = Set(programs.filter { $0.liftName == liftName && $0.unit == unit }.map(\.id))
        return workouts
            .filter { $0.status == .completed && $0.id != workoutID && programIDs.contains($0.programID) }
            .compactMap(Self.estimatedOneRepMax(of:))
            .max()
    }

    static func estimatedOneRepMax(of workout: Workout) -> Double? {
        guard let set = workout.sets.last(where: { $0.kind == .main && $0.isAMRAP && $0.isCompleted }), set.reps > 0 else {
            return nil
        }
        return StrengthMath.estimatedOneRepMax(weight: set.weight, reps: set.reps)
    }

    // MARK: - Accessory history

    private var startedWorkoutsNewestFirst: [Workout] {
        workouts.filter(\.isStarted).sorted { ($0.startedAt ?? $0.scheduledDate) > ($1.startedAt ?? $1.scheduledDate) }
    }

    func lastAccessory(named name: String, excluding workoutID: UUID? = nil) -> AccessoryExercise? {
        let key = name.lowercased()
        return startedWorkoutsNewestFirst
            .lazy
            .filter { $0.id != workoutID }
            .compactMap { $0.accessories.last { $0.name.lowercased() == key } }
            .first
    }

    func recentAccessoryNames(limit: Int = 15) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for workout in startedWorkoutsNewestFirst {
            for accessory in workout.accessories where seen.insert(accessory.name.lowercased()).inserted {
                names.append(accessory.name)
            }
        }
        return Array(names.prefix(limit))
    }

    // MARK: - Programs

    @discardableResult
    func createProgram(_ program: Program, now: Date = .now) -> Program {
        var program = program
        program.startDate = calendar.startOfDay(for: program.startDate)
        program.generatedThrough = nil
        programs.append(program)
        normalize(programID: program.id, now: now)
        return program
    }

    /// For name, color and template options. Use `updateSchedule` for days/frequency.
    func updateProgram(_ id: UUID, _ body: (inout Program) -> Void) {
        guard let index = programIndex(id) else { return }
        body(&programs[index])
        setNeedsSave()
    }

    func deleteProgram(_ id: UUID) {
        programs.removeAll { $0.id == id }
        workouts.removeAll { $0.programID == id }
        setNeedsSave()
    }

    /// Ends a program: keeps its history, drops its future plan.
    func archiveProgram(_ id: UUID) {
        guard let index = programIndex(id) else { return }
        programs[index].isArchived = true
        workouts.removeAll { $0.programID == id && $0.status == .planned }
        setNeedsSave()
    }

    func restoreProgram(_ id: UUID, now: Date = .now) {
        guard let index = programIndex(id) else { return }
        programs[index].isArchived = false
        programs[index].generatedThrough = nil
        normalize(programID: id, now: now)
    }

    func currentCycle(programID: UUID) -> Int {
        currentHeader(programID: programID)?.cycle ?? 0
    }

    /// Sets a new training max from the current cycle onward; later cycles keep adding the increment.
    func adjustTrainingMax(programID: UUID, to value: Double, now: Date = .now) {
        guard value > 0, let index = programIndex(programID), var settings = programs[index].fiveThreeOne else { return }
        settings.trainingMaxAdjustments = FiveThreeOne.adjustments(
            settingTrainingMax: value,
            fromCycle: currentCycle(programID: programID),
            date: now,
            settings: settings
        )
        programs[index].fiveThreeOne = settings
        setNeedsSave()
    }

    /// Changes days/frequency and re-plans every planned workout onto the new days from today.
    func updateSchedule(programID: UUID, to schedule: WeeklySchedule, now: Date = .now) {
        guard schedule.isValid, let index = programIndex(programID) else { return }
        renumber(programID: programID)
        if var settings = programs[index].fiveThreeOne {
            let nextSession = nextWorkout(programID: programID)?.sessionIndex
                ?? ((workouts(programID: programID).filter(\.isStarted).map(\.sessionIndex).max() ?? -1) + 1)
            settings.segments = FiveThreeOne.segments(
                changingSessionsPerWeekTo: schedule.sessionsPerWeek,
                effectiveFromSession: nextSession,
                settings: settings
            )
            programs[index].fiveThreeOne = settings
        }
        programs[index].schedule = schedule

        let anchor = max(calendar.startOfDay(for: now), calendar.startOfDay(for: programs[index].startDate))
        var day = ScheduleMath.nextDate(onOrAfter: anchor, weekdays: schedule.weekdays, calendar)
        var plan: [UUID: Date] = [:]
        for (offset, workout) in plannedWorkouts(programID: programID).enumerated() {
            if offset > 0 { day = ScheduleMath.nextDate(after: day, weekdays: schedule.weekdays, calendar) }
            plan[workout.id] = day
        }
        apply(plan)
        programs[index].generatedThrough = plan.values.max() ?? ScheduleMath.addingDays(-1, to: anchor, calendar)
        normalize(programID: programID, now: now)
    }

    // MARK: - Moving workouts

    /// New dates for every workout the reschedule would touch.
    func planReschedule(workoutID: UUID, to newDate: Date, scope: RescheduleScope) -> [UUID: Date] {
        guard let workout = workout(workoutID), workout.status == .planned, let program = program(workout.programID) else {
            return [:]
        }
        let target = calendar.startOfDay(for: newDate)
        switch scope {
        case .onlyThis:
            return [workout.id: target]
        case .thisAndFollowing(let style):
            let following = plannedWorkouts(programID: program.id).filter { !Self.scheduleOrder($0, workout) }
            switch style {
            case .keepSpacing:
                let delta = ScheduleMath.days(from: workout.scheduledDate, to: target, calendar)
                return Dictionary(uniqueKeysWithValues: following.map {
                    ($0.id, ScheduleMath.addingDays(delta, to: $0.scheduledDate, calendar))
                })
            case .fitToSchedule:
                var plan: [UUID: Date] = [:]
                var day = target
                for (offset, item) in following.enumerated() {
                    if offset > 0 { day = ScheduleMath.nextDate(after: day, weekdays: program.schedule.weekdays, calendar) }
                    plan[item.id] = day
                }
                return plan
            }
        }
    }

    func reschedule(workoutID: UUID, to newDate: Date, scope: RescheduleScope, now: Date = .now) {
        guard let workout = workout(workoutID), let index = programIndex(workout.programID) else { return }
        let plan = planReschedule(workoutID: workoutID, to: newDate, scope: scope)
        guard !plan.isEmpty else { return }
        apply(plan)
        switch scope {
        case .onlyThis:
            break
        case .thisAndFollowing(.keepSpacing):
            if let through = programs[index].generatedThrough {
                let delta = ScheduleMath.days(from: workout.scheduledDate, to: newDate, calendar)
                programs[index].generatedThrough = ScheduleMath.addingDays(delta, to: through, calendar)
            }
        case .thisAndFollowing(.fitToSchedule):
            programs[index].generatedThrough = plan.values.max()
        }
        normalize(programID: workout.programID, now: now)
    }

    func planShift(programID: UUID, days: Int) -> [UUID: Date] {
        Dictionary(uniqueKeysWithValues: plannedWorkouts(programID: programID).map {
            ($0.id, ScheduleMath.addingDays(days, to: $0.scheduledDate, calendar))
        })
    }

    /// Pushes every planned workout of the program back (or forward) by `days`.
    func shiftProgram(programID: UUID, days: Int, now: Date = .now) {
        guard days != 0, let index = programIndex(programID) else { return }
        apply(planShift(programID: programID, days: days))
        if let through = programs[index].generatedThrough {
            programs[index].generatedThrough = ScheduleMath.addingDays(days, to: through, calendar)
        }
        normalize(programID: programID, now: now)
    }

    private func apply(_ plan: [UUID: Date]) {
        guard !plan.isEmpty else { return }
        for index in workouts.indices {
            if let date = plan[workouts[index].id], workouts[index].scheduledDate != date {
                workouts[index].scheduledDate = date
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
            changed = true
        }
        return changed
    }

    /// Generates planned workouts on the program's days up to the horizon.
    @discardableResult
    private func topUp(programID: UUID, now: Date) -> Bool {
        guard let index = programIndex(programID) else { return false }
        let program = programs[index]
        guard program.schedule.isValid, !program.isArchived else { return false }
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: program.startDate)
        let horizonEnd = ScheduleMath.addingDays(horizonDays, to: max(today, start), calendar)
        let from = program.generatedThrough.map { max(ScheduleMath.addingDays(1, to: $0, calendar), today) } ?? max(start, today)
        guard from <= horizonEnd else { return false }

        let dates = ScheduleMath.dates(from: from, through: horizonEnd, weekdays: program.schedule.weekdays, calendar)
        var nextIndex = (workouts(programID: programID).map(\.sessionIndex).max() ?? -1) + 1
        for date in dates {
            workouts.append(Workout(programID: programID, sessionIndex: nextIndex, scheduledDate: date))
            nextIndex += 1
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
        setNeedsSave()
    }

    /// Freezes the prescription into real sets and starts the clock.
    func startWorkout(_ id: UUID, now: Date = .now) {
        guard let workout = workout(id), workout.status == .planned,
              let prescription = prescription(for: workout) else { return }
        mutateWorkout(id) {
            $0.status = .inProgress
            $0.startedAt = now
            $0.header = prescription.header
            $0.sets = prescription.sets.map {
                WorkoutSet(kind: $0.kind, targetWeight: $0.weight, targetReps: $0.reps, isAMRAP: $0.isAMRAP,
                           percentOfTM: $0.percentOfTM, weight: $0.weight, reps: $0.reps)
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

        let done = workout.sets.filter(\.isCompleted)
        let amrap = workout.sets.last { $0.kind == .main && $0.isAMRAP }
        let header = workout.header ?? prescription(for: workout)?.header
        let cycle = header.flatMap { ProgramEngine.cycleCompletion(for: program, header: $0) }
        return CompletionSummary(
            workoutID: id,
            programID: program.id,
            title: header?.title ?? program.liftName,
            subtitle: header?.subtitle ?? program.name,
            unit: program.unit,
            duration: now.timeIntervalSince(workout.startedAt ?? now),
            completedSets: done.count,
            totalSets: workout.sets.count,
            volume: done.reduce(0) { $0 + $1.weight * Double($1.reps) },
            accessorySets: workout.accessories.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count },
            amrapWeight: amrap?.weight,
            amrapReps: amrap.flatMap { $0.isCompleted ? $0.reps : nil },
            amrapTarget: amrap?.targetReps,
            estimatedOneRepMax: Self.estimatedOneRepMax(of: workout),
            previousBestOneRepMax: bestEstimatedOneRepMax(liftName: program.liftName, unit: program.unit, excluding: id),
            completedCycle: cycle?.cycle,
            nextTrainingMax: cycle?.nextTrainingMax,
            streak: streak().current
        )
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

    func updateSet(workoutID: UUID, setID: UUID, _ body: (inout WorkoutSet) -> Void) {
        mutateWorkout(workoutID) { workout in
            guard let index = workout.sets.firstIndex(where: { $0.id == setID }) else { return }
            body(&workout.sets[index])
        }
    }

    // MARK: - Accessories

    /// Adds an accessory, pre-filled with what you did last time (or 3×10).
    @discardableResult
    func addAccessory(to workoutID: UUID, named rawName: String) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, workout(workoutID) != nil else { return nil }
        let previous = lastAccessory(named: name, excluding: workoutID)
        let sets = previous.map { $0.sets.map { AccessorySet(weight: $0.weight, reps: $0.reps) } } ?? []
        let exercise = AccessoryExercise(
            name: previous?.name ?? name,
            sets: sets.isEmpty ? (0..<3).map { _ in AccessorySet(weight: 0, reps: 10) } : sets
        )
        mutateWorkout(workoutID) { $0.accessories.append(exercise) }
        return exercise.id
    }

    func removeAccessory(workoutID: UUID, accessoryID: UUID) {
        mutateWorkout(workoutID) { $0.accessories.removeAll { $0.id == accessoryID } }
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
            accessory.sets.append(AccessorySet(weight: last?.weight ?? 0, reps: last?.reps ?? 10))
        }
    }

    func removeAccessorySet(workoutID: UUID, accessoryID: UUID, setID: UUID) {
        mutateAccessory(workoutID: workoutID, accessoryID: accessoryID) { accessory, _ in
            accessory.sets.removeAll { $0.id == setID }
        }
    }

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
