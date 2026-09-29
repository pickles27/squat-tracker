import Foundation
@testable import SquatsCore

enum TestCalendar {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()

    /// yyyy-MM-dd at midnight UTC, optionally with an hour.
    static func date(_ string: String, hour: Int = 0) -> Date {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    static func string(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}

enum Weekday {
    static let sunday = 1, monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7
}

@MainActor
func makeStore() -> WorkoutStore {
    WorkoutStore(fileURL: nil, calendar: TestCalendar.calendar)
}

func makeProgram(
    trainingMax: Double = 100,
    weekdays: Set<Int> = [Weekday.monday, Weekday.wednesday, Weekday.friday],
    start: String = "2026-09-28",
    advanceMode: AdvanceMode = .perTrainingWeek,
    warmups: Bool = true
) -> Program {
    Program(
        name: "5/3/1 Squat",
        kind: .fiveThreeOne,
        unit: .kg,
        createdAt: TestCalendar.date(start),
        startDate: TestCalendar.date(start),
        schedule: WeeklySchedule(sessionsPerWeek: weekdays.count, weekdays: weekdays),
        fiveThreeOne: FiveThreeOneSettings(
            startingTrainingMax: trainingMax,
            cycleIncrement: 5,
            rounding: 2.5,
            includeWarmups: warmups,
            advanceMode: advanceMode,
            sessionsPerWeek: weekdays.count
        )
    )
}
