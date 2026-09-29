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

let monWedFri: Set<Int> = [Weekday.monday, Weekday.wednesday, Weekday.friday]

@MainActor
func makeStore(now: Date = TestCalendar.date("2026-09-28", hour: 10)) -> WorkoutStore {
    let store = WorkoutStore(fileURL: nil, calendar: TestCalendar.calendar)
    store.clock = { now }
    return store
}

func makeProgram(
    squat: Double = 100,
    bench: Double = 60,
    deadlift: Double = 140,
    weekdays: Set<Int> = monWedFri,
    start: String = "2026-09-28",
    options: FiveThreeOneBeginners.Options = .init(),
    unit: WeightUnit = .kg,
    rounding: Double = 2.5
) -> Program {
    FiveThreeOneBeginners.makeProgram(
        name: "5/3/1 for Beginners",
        unit: unit,
        rounding: rounding,
        lifts: [
            .init(liftID: "squat", trainingMax: squat),
            .init(liftID: "bench", trainingMax: bench),
            .init(liftID: "deadlift", trainingMax: deadlift),
        ],
        options: options,
        weekdays: weekdays,
        startDate: TestCalendar.date(start),
        colorIndex: 0,
        now: TestCalendar.date(start)
    )
}

/// "65x5", "85x5+", "115x3-5+" style descriptions of one lift's sets of a kind.
func describe(_ sets: [PrescribedSet], lift: String, kind: SetKind = .main) -> [String] {
    sets.filter { $0.liftID == lift && $0.kind == kind }.map {
        "\(WeightFormat.plain($0.weight))x\($0.reps)\($0.maxReps.map { "-\($0)" } ?? "")\($0.isAMRAP ? "+" : "")"
    }
}

@MainActor
func completeNext(_ store: WorkoutStore, programID: UUID, now: Date, amrapReps: Int? = nil) -> CompletionSummary? {
    guard let next = store.nextWorkout(programID: programID) else { return nil }
    store.startWorkout(next.id, now: now)
    for set in store.workout(next.id)!.sets {
        store.toggleSet(workoutID: next.id, setID: set.id, now: now)
        if set.isAMRAP, let amrapReps {
            store.updateSet(workoutID: next.id, setID: set.id) { $0.reps = amrapReps }
        }
    }
    return store.completeWorkout(next.id, now: now)
}
