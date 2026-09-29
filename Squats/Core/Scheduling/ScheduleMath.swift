import Foundation

/// Day-level date math. Everything works on the start of the day in the given calendar.
enum ScheduleMath {
    static func addingDays(_ days: Int, to date: Date, _ calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard let moved = calendar.date(byAdding: .day, value: days, to: start) else {
            return start.addingTimeInterval(Double(days) * 86_400)
        }
        return calendar.startOfDay(for: moved)
    }

    static func days(from start: Date, to end: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    static func weekday(of date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.weekday, from: date)
    }

    static func nextDate(onOrAfter date: Date, weekdays: Set<Int>, _ calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: date)
        guard !weekdays.isEmpty else { return day }
        for _ in 0..<7 {
            if weekdays.contains(weekday(of: day, calendar)) { return day }
            day = addingDays(1, to: day, calendar)
        }
        return day
    }

    static func nextDate(after date: Date, weekdays: Set<Int>, _ calendar: Calendar) -> Date {
        nextDate(onOrAfter: addingDays(1, to: date, calendar), weekdays: weekdays, calendar)
    }

    /// Every day in `start...end` that falls on one of `weekdays`.
    static func dates(from start: Date, through end: Date, weekdays: Set<Int>, _ calendar: Calendar) -> [Date] {
        guard !weekdays.isEmpty else { return [] }
        let last = calendar.startOfDay(for: end)
        var result: [Date] = []
        var day = nextDate(onOrAfter: start, weekdays: weekdays, calendar)
        while day <= last {
            result.append(day)
            day = nextDate(after: day, weekdays: weekdays, calendar)
        }
        return result
    }
}
