import Foundation

/// Jim Wendler's "5/3/1 for Beginners" as described on thefitness.wiki, without overhead press:
/// Day 1 Squat + Bench, Day 2 Deadlift, Day 3 Bench + Squat. 3-week cycles with First Set Last 5×5,
/// training max +increment after every cycle, and a TM test week after every third cycle.
enum FiveThreeOneBeginners {
    static let templateID = "531-beginners"

    static let squat = TemplateLift(id: "squat", name: "Squat", isLowerBody: true)
    static let bench = TemplateLift(id: "bench", name: "Bench Press", isLowerBody: false)
    static let deadlift = TemplateLift(id: "deadlift", name: "Deadlift", isLowerBody: true)
    static let lifts = [squat, bench, deadlift]

    static let weekNames = ["5s", "3s", "5/3/1"]
    static let trainingDays = [["squat", "bench"], ["deadlift"], ["bench", "squat"]]
    static let testDays = [["squat"], ["bench"], ["deadlift"]]

    static let warmupSets = [
        SetScheme(kind: .warmup, percent: 0.40, reps: 5),
        SetScheme(kind: .warmup, percent: 0.50, reps: 5),
        SetScheme(kind: .warmup, percent: 0.60, reps: 3),
    ]

    static func mainSets(week: Int) -> [SetScheme] {
        let scheme: [(Double, Int)] = switch week {
        case 0: [(0.65, 5), (0.75, 5), (0.85, 5)]
        case 1: [(0.70, 3), (0.80, 3), (0.90, 3)]
        default: [(0.75, 5), (0.85, 3), (0.95, 1)]
        }
        return scheme.enumerated().map { index, set in
            SetScheme(kind: .main, percent: set.0, reps: set.1, isAMRAP: index == scheme.count - 1)
        }
    }

    /// 5×5 at the first working set's percentage.
    static func firstSetLast(week: Int) -> [SetScheme] {
        let percent = mainSets(week: week)[0].percent
        return Array(repeating: SetScheme(kind: .supplemental, percent: percent, reps: 5), count: 5)
    }

    /// TM test: 70%×5, 80%×5, 90%×3, then 100% for 3–5 reps. Fewer than 3 at 100% means the TM is too high.
    static let testSets = [
        SetScheme(kind: .main, percent: 0.70, reps: 5),
        SetScheme(kind: .main, percent: 0.80, reps: 5),
        SetScheme(kind: .main, percent: 0.90, reps: 3),
        SetScheme(kind: .main, percent: 1.00, reps: 3, isAMRAP: true, maxReps: 5),
    ]

    struct Options: Hashable, Sendable {
        var includeWarmups = true
        var includeTestWeek = true
    }

    static func template(_ options: Options = Options()) -> ProgramTemplate {
        var weeks: [TemplateWeek] = []
        let cycles = options.includeTestWeek ? 3 : 1
        for cycle in 0..<cycles {
            for week in 0..<3 {
                let sets = (options.includeWarmups ? warmupSets : []) + mainSets(week: week) + firstSetLast(week: week)
                weeks.append(TemplateWeek(
                    name: "Week \(week + 1) · \(weekNames[week])",
                    kind: .training,
                    cycleInBlock: cycle,
                    increasesTrainingMaxAfter: week == 2,
                    days: trainingDays.map { TemplateDay(lifts: $0.map { LiftWork(liftID: $0, sets: sets) }) }
                ))
            }
        }
        if options.includeTestWeek {
            weeks.append(TemplateWeek(
                name: "TM Test Week",
                kind: .test,
                cycleInBlock: nil,
                increasesTrainingMaxAfter: false,
                days: testDays.map { TemplateDay(lifts: $0.map { LiftWork(liftID: $0, sets: testSets) }) }
            ))
        }
        return ProgramTemplate(
            id: templateID,
            name: "5/3/1 for Beginners",
            summary: "Squat, bench and deadlift 3 days a week. 3-week cycles of 5s, 3s and 5/3/1 plus 5×5 First Set Last; training max goes up every cycle, with a TM test every 10th week.",
            isBuiltIn: true,
            dayRequirement: .exactly(3),
            trainingMaxPercent: 0.9,
            lifts: lifts,
            weeks: weeks
        )
    }

    static func increment(for lift: TemplateLift, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: lift.isLowerBody ? 5 : 2.5
        case .lb: lift.isLowerBody ? 10 : 5
        }
    }

    /// Starting TM from a set taken to 3–5 good reps: 90% of the estimated 1RM, rounded.
    static func trainingMax(fromWeight weight: Double, reps: Int, rounding: Double) -> Double {
        StrengthMath.round(StrengthMath.estimatedOneRepMax(weight: weight, reps: reps) * 0.9, to: rounding)
    }

    struct LiftSetup: Hashable, Sendable {
        var liftID: String
        var trainingMax: Double
        var testWeight: Double?
        var testReps: Int?
    }

    static func makeProgram(
        name: String,
        unit: WeightUnit,
        rounding: Double,
        lifts setups: [LiftSetup],
        options: Options,
        weekdays: Set<Int>,
        startDate: Date,
        colorIndex: Int,
        now: Date = .now
    ) -> Program {
        let template = template(options)
        let programLifts = template.lifts.map { lift in
            let setup = setups.first { $0.liftID == lift.id }
            return ProgramLift(
                id: lift.id,
                name: lift.name,
                startingTrainingMax: setup?.trainingMax ?? 0,
                increment: increment(for: lift, unit: unit),
                testWeight: setup?.testWeight,
                testReps: setup?.testReps
            )
        }
        return Program(
            name: name,
            template: template,
            unit: unit,
            rounding: rounding,
            lifts: programLifts,
            colorIndex: colorIndex,
            createdAt: now,
            updatedAt: now,
            startDate: startDate,
            schedule: WeeklySchedule(sessionsPerWeek: template.daysPerWeek, weekdays: weekdays)
        )
    }
}
