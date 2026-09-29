import Foundation

/// How often and on which days the user trains.
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

    /// The same pattern moved by `days` (Mon/Wed/Fri shifted by 1 → Tue/Thu/Sat).
    func rotated(byDays days: Int) -> WeeklySchedule {
        let shift = ((days % 7) + 7) % 7
        guard shift != 0 else { return self }
        var copy = self
        copy.weekdays = Set(weekdays.map { ($0 - 1 + shift) % 7 + 1 })
        return copy
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

/// A main lift as configured for one program.
struct ProgramLift: Codable, Hashable, Identifiable, Sendable {
    /// Matches `TemplateLift.id`, e.g. "squat".
    var id: String
    var name: String
    var startingTrainingMax: Double
    /// Training-max increase per cycle.
    var increment: Double
    /// The set used to estimate the starting max, if one was entered.
    var testWeight: Double?
    var testReps: Int?
}

/// Manual or suggested training-max change for one lift, applying from `fromProgramWeek` onward.
struct TrainingMaxAdjustment: Codable, Hashable, Sendable {
    var liftID: String
    var fromProgramWeek: Int
    var trainingMax: Double
    var date: Date
    var reason: String?
}

/// Top-level container: template, lifts, schedule, and (via `Workout.programID`) history and future plan.
struct Program: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Resolved copy of the template, so a program never changes if built-ins are updated.
    var template: ProgramTemplate
    var unit: WeightUnit
    var rounding: Double
    var lifts: [ProgramLift]
    var trainingMaxAdjustments: [TrainingMaxAdjustment] = []
    var colorIndex: Int = 0
    var createdAt: Date
    var updatedAt: Date
    var startDate: Date
    var schedule: WeeklySchedule
    /// Last day the automatic schedule has been generated through.
    var generatedThrough: Date?
    /// Finished programs keep their history but stop scheduling workouts.
    var isArchived = false

    func lift(_ id: String) -> ProgramLift? {
        lifts.first { $0.id == id }
    }
}
