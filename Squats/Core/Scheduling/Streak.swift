import Foundation

struct StreakSummary: Hashable, Sendable {
    var current: Int
    var best: Int

    static let zero = StreakSummary(current: 0, best: 0)
}

/// A streak counts planned workouts completed in a row. It breaks when a workout is missed
/// (its day plus the grace day passes without it being done or moved) or skipped on/after its day.
/// Skipping ahead of time counts as re-planning and doesn't break it.
enum StreakCalculator {
    struct Event: Hashable {
        var date: Date
        var isSuccess: Bool
    }

    static func events(for workouts: [Workout]) -> [Event] {
        var events: [Event] = []
        for workout in workouts {
            if let missed = workout.missedOn {
                events.append(Event(date: missed, isSuccess: false))
            }
            switch workout.status {
            case .completed:
                if let completed = workout.completedAt {
                    events.append(Event(date: completed, isSuccess: true))
                }
            case .skipped:
                if workout.missedOn == nil, let skipped = workout.skippedAt, skipped >= workout.scheduledDate {
                    events.append(Event(date: workout.scheduledDate, isSuccess: false))
                }
            case .planned, .inProgress:
                break
            }
        }
        return events.sorted { lhs, rhs in
            lhs.date == rhs.date ? (!lhs.isSuccess && rhs.isSuccess) : lhs.date < rhs.date
        }
    }

    static func summary(for workouts: [Workout]) -> StreakSummary {
        var current = 0
        var best = 0
        for event in events(for: workouts) {
            if event.isSuccess {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return StreakSummary(current: current, best: best)
    }
}
