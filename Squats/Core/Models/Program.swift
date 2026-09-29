import Foundation

/// The kinds of programs the app can generate. Add a case (plus an engine) to support more.
enum ProgramKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveThreeOne

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fiveThreeOne: "5/3/1"
        }
    }

    var fullName: String {
        switch self {
        case .fiveThreeOne: "Wendler 5/3/1"
        }
    }

    var summary: String {
        switch self {
        case .fiveThreeOne:
            "Cycles of 5s, 3s and 5/3/1 weeks off a training max, then a deload. The training max goes up every cycle."
        }
    }
}

/// How often and on which days the user is willing to train.
struct WeeklySchedule: Codable, Hashable, Sendable {
    var sessionsPerWeek: Int
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>

    init(sessionsPerWeek: Int, weekdays: Set<Int> = []) {
        self.sessionsPerWeek = sessionsPerWeek
        self.weekdays = weekdays
    }

    /// Valid only when exactly `sessionsPerWeek` days are picked, so the schedule is never ambiguous.
    var isValid: Bool {
        (1...7).contains(sessionsPerWeek)
            && weekdays.count == sessionsPerWeek
            && weekdays.allSatisfy { (1...7).contains($0) }
    }

    var validationMessage: String? {
        let missing = sessionsPerWeek - weekdays.count
        if missing > 0 { return "Pick \(missing) more day\(missing == 1 ? "" : "s")" }
        if missing < 0 { return "Deselect \(-missing) day\(missing == -1 ? "" : "s")" }
        return nil
    }

    /// Weekday numbers in display order, starting from the calendar's first weekday.
    static func displayOrder(_ calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    func orderedWeekdays(_ calendar: Calendar) -> [Int] {
        Self.displayOrder(calendar).filter(weekdays.contains)
    }

    func daysDescription(_ calendar: Calendar) -> String {
        orderedWeekdays(calendar).map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}

/// Top-level container: settings, schedule, and (via `Workout.programID`) the history and future plan.
struct Program: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: ProgramKind
    var liftName: String = "Squat"
    var unit: WeightUnit
    var colorIndex: Int = 0
    var createdAt: Date
    var startDate: Date
    var schedule: WeeklySchedule
    /// Last day the automatic schedule has been generated through.
    var generatedThrough: Date?
    var fiveThreeOne: FiveThreeOneSettings?
    /// Finished programs keep their history but stop scheduling workouts.
    var isArchived = false
}
