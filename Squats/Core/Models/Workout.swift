import Foundation

enum WorkoutStatus: String, Codable, Sendable {
    case planned
    case inProgress
    case completed
    case skipped
}

enum SetKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case main
    case supplemental

    var title: String {
        switch self {
        case .warmup: "Warm-up"
        case .main: "Main sets"
        case .supplemental: "Supplemental"
        }
    }
}

/// A barbell set for the program's main lift. Targets come from the program; actuals are what was lifted.
struct WorkoutSet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: SetKind
    var targetWeight: Double
    var targetReps: Int
    var isAMRAP: Bool
    var percentOfTM: Double?
    var weight: Double
    var reps: Int
    var isCompleted = false
    var completedAt: Date?
}

struct AccessorySet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var weight: Double
    var reps: Int
    var isCompleted = false
    var completedAt: Date?
}

/// Free-form extra exercise logged during a workout (never programmed ahead of time).
struct AccessoryExercise: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var sets: [AccessorySet]
}

/// Snapshot of where a session sits in its program, e.g. "Week 1 · 5s", cycle 2.
struct SessionHeader: Codable, Hashable, Sendable {
    var title: String
    var subtitle: String
    /// 0-based.
    var cycle: Int
    /// 0-based week within the cycle.
    var week: Int
    /// 0-based day within the program week.
    var dayInWeek: Int
    var sessionsInWeek: Int
    var trainingMax: Double
    var isDeload: Bool
}

struct Workout: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var programID: UUID
    /// Position in the program's sequence; decides the prescription while the workout is still planned.
    var sessionIndex: Int
    /// Start of the scheduled day.
    var scheduledDate: Date
    var status: WorkoutStatus = .planned
    var startedAt: Date?
    var completedAt: Date?
    var skippedAt: Date?
    /// Set when the workout's day (plus grace) passed without it being done or moved. Breaks the streak.
    var missedOn: Date?
    /// Frozen when the workout starts (or is skipped) so history never changes afterwards.
    var header: SessionHeader?
    var sets: [WorkoutSet] = []
    var accessories: [AccessoryExercise] = []
    var notes: String = ""
    var lastSetCompletedAt: Date?

    var isStarted: Bool { status == .inProgress || status == .completed }
}
