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
        case .supplemental: "First Set Last"
        }
    }
}

/// A barbell set for one of the program's main lifts. Expected values come from the program;
/// actual values are what was really lifted (pre-filled with the expected ones).
struct WorkoutSet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var liftID: String
    var liftName: String
    var kind: SetKind
    var targetWeight: Double
    var targetReps: Int
    /// AMRAP sets have a minimum (`targetReps`) and sometimes a cap, e.g. the TM test's 3–5.
    var isAMRAP: Bool
    var maxReps: Int?
    var percentOfTM: Double?
    var weight: Double
    var reps: Int
    var isCompleted = false
    var completedAt: Date?

    var missedTarget: Bool { isCompleted && reps < targetReps }
}

/// Accessory set. Targets are optional: set from last time or by the user.
struct AccessorySet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var targetWeight: Double?
    var targetReps: Int?
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

/// Snapshot of where a session sits in its program, e.g. "Week 1 · 5s", cycle 2, day 1 of 3.
struct SessionHeader: Codable, Hashable, Sendable {
    var title: String
    var subtitle: String
    /// 0-based week counted from the program start.
    var programWeek: Int
    /// 0-based global cycle; nil for weeks between cycles (e.g. a TM test week).
    var cycle: Int?
    var weekKind: WeekKind
    var dayInWeek: Int
    var daysInWeek: Int
    var liftNames: [String]
    /// Lift ID → training max used for this session.
    var trainingMaxes: [String: Double]
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
    var updatedAt: Date = .distantPast

    var isStarted: Bool { status == .inProgress || status == .completed }
}
