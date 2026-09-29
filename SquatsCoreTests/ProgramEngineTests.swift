import Foundation
import Testing
@testable import SquatsCore

struct ProgramEngineTests {
    let program = makeProgram()

    func prescription(_ session: Int, _ program: Program? = nil) -> SessionPrescription {
        ProgramEngine.prescription(for: program ?? self.program, session: session)
    }

    @Test func templateShape() {
        let template = FiveThreeOneBeginners.template()
        #expect(template.isValid)
        #expect(template.daysPerWeek == 3)
        #expect(template.dayRequirement == .exactly(3))
        #expect(template.weeks.count == 10)
        #expect(template.cyclesPerBlock == 3)
        #expect(FiveThreeOneBeginners.template(.init(includeTestWeek: false)).weeks.count == 3)
    }

    @Test func dayLayout() {
        #expect(prescription(0).liftIDs == ["squat", "bench"])
        #expect(prescription(1).liftIDs == ["deadlift"])
        #expect(prescription(2).liftIDs == ["bench", "squat"])
        #expect(prescription(0).header.subtitle == "Cycle 1 · Day 1 of 3")
        #expect(prescription(0).header.liftNames == ["Squat", "Bench Press"])
    }

    @Test func weeklyPercentages() {
        #expect(describe(prescription(0).sets, lift: "squat") == ["65x5", "75x5", "85x5+"])
        #expect(describe(prescription(3).sets, lift: "squat") == ["70x3", "80x3", "90x3+"])
        #expect(describe(prescription(6).sets, lift: "squat") == ["75x5", "85x3", "95x1+"])
        #expect(prescription(6).header.title == "Week 3 · 5/3/1")
        // Deadlift TM 140: 91 → 90, 105, 119 → 120
        #expect(describe(prescription(1).sets, lift: "deadlift") == ["90x5", "105x5", "120x5+"])
    }

    @Test func warmupAndFirstSetLast() {
        let week2 = prescription(3).sets
        #expect(describe(week2, lift: "squat", kind: .warmup) == ["40x5", "50x5", "60x3"])
        #expect(describe(week2, lift: "squat", kind: .supplemental) == Array(repeating: "70x5", count: 5))
        #expect(prescription(0, makeProgram(options: .init(includeWarmups: false))).sets.allSatisfy { $0.kind != .warmup })
        #expect(prescription(0).sets.count == 22) // 2 lifts × (3 warm-up + 3 main + 5 FSL)
    }

    @Test func matchesArticleExample() {
        // thefitness.wiki: squat TM 190 lb → 125 / 140 / 160+ then 5×5 @ 125; bench TM 140 → 90 / 105 / 120+
        let lb = makeProgram(squat: 190, bench: 140, unit: .lb, rounding: 5)
        #expect(describe(prescription(0, lb).sets, lift: "squat") == ["125x5", "140x5", "160x5+"])
        #expect(Set(describe(prescription(0, lb).sets, lift: "squat", kind: .supplemental)) == ["125x5"])
        #expect(describe(prescription(0, lb).sets, lift: "bench") == ["90x5", "105x5", "120x5+"])
    }

    @Test func trainingMaxGoesUpAfterEachCycle() {
        let cycle2 = prescription(9)
        #expect(cycle2.header.cycle == 1)
        #expect(cycle2.header.title == "Week 1 · 5s")
        #expect(cycle2.header.trainingMaxes == ["squat": 105, "bench": 62.5])
        #expect(prescription(10).header.trainingMaxes == ["deadlift": 145])
    }

    @Test func testWeekAfterThreeCycles() {
        let test = prescription(27)
        #expect(test.header.weekKind == .test)
        #expect(test.header.title == "TM Test Week")
        #expect(test.header.cycle == nil)
        #expect(test.liftIDs == ["squat"])
        #expect(test.header.trainingMaxes["squat"] == 115)
        #expect(describe(test.sets, lift: "squat") == ["80x5", "92.5x5", "102.5x3", "115x3-5+"])
        #expect(prescription(28).liftIDs == ["bench"])
        #expect(prescription(29).liftIDs == ["deadlift"])
        // The next cycle keeps the test week's TM.
        let next = prescription(30)
        #expect(next.header.cycle == 3)
        #expect(next.header.trainingMaxes["squat"] == 115)
    }

    @Test func withoutTestWeekCyclesRunBackToBack() {
        let noTest = makeProgram(options: .init(includeTestWeek: false))
        #expect(prescription(9, noTest).header.cycle == 1)
        #expect(prescription(27, noTest).header.cycle == 3)
        #expect(prescription(27, noTest).header.trainingMaxes["squat"] == 115)
    }

    @Test func incrementsPerLift() {
        #expect(program.lift("squat")?.increment == 5)
        #expect(program.lift("bench")?.increment == 2.5)
        let lb = makeProgram(unit: .lb, rounding: 5)
        #expect(lb.lift("deadlift")?.increment == 10)
        #expect(lb.lift("bench")?.increment == 5)
    }

    @Test func adjustmentsApplyForwardPerLift() {
        var adjusted = program
        adjusted.trainingMaxAdjustments = [TrainingMaxAdjustment(liftID: "squat", fromProgramWeek: 3, trainingMax: 90, date: .now)]
        #expect(ProgramEngine.trainingMax(liftID: "squat", programWeek: 2, program: adjusted) == 100)
        #expect(ProgramEngine.trainingMax(liftID: "squat", programWeek: 3, program: adjusted) == 90)
        #expect(ProgramEngine.trainingMax(liftID: "squat", programWeek: 6, program: adjusted) == 95)
        #expect(ProgramEngine.trainingMax(liftID: "bench", programWeek: 3, program: adjusted) == 62.5)
    }

    @Test func startingMaxFromRepSet() {
        // 100 × 5 → e1RM 116.65 → 90% = 104.985 → 105
        #expect(FiveThreeOneBeginners.trainingMax(fromWeight: 100, reps: 5, rounding: 2.5) == 105)
    }

    @Test func rounding() {
        #expect(StrengthMath.round(142.5, to: 5) == 140)
        #expect(StrengthMath.round(142.6, to: 5) == 145)
        #expect(StrengthMath.round(76.375, to: 2.5) == 77.5)
        #expect(StrengthMath.round(76.2, to: 2.5) == 75)
        #expect(StrengthMath.round(101.1, to: 1.25) == 101.25)
        #expect(StrengthMath.round(0.4, to: 2.5) == 0)
    }

    @Test func oneRepMaxEstimate() {
        #expect(StrengthMath.estimatedOneRepMax(weight: 100, reps: 5) == 116.65)
        #expect(StrengthMath.estimatedOneRepMax(weight: 100, reps: 1) == 100)
        #expect(StrengthMath.estimatedOneRepMax(weight: 100, reps: 0) == 0)
    }

    @Test func plateLoadout() {
        #expect(PlateCalculator.loadout(for: 102.5, unit: .kg)?.perSide == [25, 15, 1.25])
        #expect(PlateCalculator.loadout(for: 20, unit: .kg)?.perSide == [])
        #expect(PlateCalculator.loadout(for: 15, unit: .kg) == nil)
        #expect(PlateCalculator.loadout(for: 225, unit: .lb)?.perSide == [45, 45])
    }

    @Test func weightFormatting() {
        #expect(WeightFormat.plain(102.5) == "102.5")
        #expect(WeightFormat.plain(100) == "100")
        #expect(WeightFormat.plain(1.25) == "1.25")
    }

    @Test func scheduleRotation() {
        let schedule = WeeklySchedule(sessionsPerWeek: 3, weekdays: monWedFri)
        #expect(schedule.rotated(byDays: 1).weekdays == [Weekday.tuesday, Weekday.thursday, Weekday.saturday])
        #expect(schedule.rotated(byDays: -1).weekdays == [Weekday.sunday, Weekday.tuesday, Weekday.thursday])
        #expect(schedule.rotated(byDays: 7) == schedule)
        #expect(WeeklySchedule(sessionsPerWeek: 3, weekdays: [Weekday.saturday]).rotated(byDays: 1).weekdays == [Weekday.sunday])
    }
}
