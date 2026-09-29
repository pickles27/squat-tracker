import Foundation
import Testing
@testable import SquatsCore

struct FiveThreeOneTests {
    func settings(
        tm: Double = 100,
        perWeek: Int = 1,
        style: MainSetStyle = .standard,
        supplemental: SupplementalTemplate = .none,
        warmups: Bool = false,
        deload: Bool = true
    ) -> FiveThreeOneSettings {
        FiveThreeOneSettings(
            startingTrainingMax: tm, cycleIncrement: 5, rounding: 2.5, includeWarmups: warmups,
            includeDeload: deload, mainSetStyle: style, supplemental: supplemental, sessionsPerWeek: perWeek
        )
    }

    func main(_ prescription: SessionPrescription) -> [String] {
        prescription.sets.filter { $0.kind == .main }.map { "\(WeightFormat.plain($0.weight))x\($0.reps)\($0.isAMRAP ? "+" : "")" }
    }

    @Test func standardCycleWeights() {
        let s = settings()
        #expect(main(FiveThreeOne.prescription(session: 0, settings: s)) == ["65x5", "75x5", "85x5+"])
        #expect(main(FiveThreeOne.prescription(session: 1, settings: s)) == ["70x3", "80x3", "90x3+"])
        #expect(main(FiveThreeOne.prescription(session: 2, settings: s)) == ["75x5", "85x3", "95x1+"])
        #expect(main(FiveThreeOne.prescription(session: 3, settings: s)) == ["40x5", "50x5", "60x5"])
    }

    @Test func trainingMaxGoesUpEachCycle() {
        let s = settings()
        let cycle2 = FiveThreeOne.prescription(session: 4, settings: s)
        #expect(cycle2.header.cycle == 1)
        #expect(cycle2.header.week == 0)
        #expect(cycle2.header.trainingMax == 105)
        #expect(main(cycle2) == ["67.5x5", "80x5", "90x5+"]) // 68.25→67.5, 78.75→80, 89.25→90
        #expect(FiveThreeOne.trainingMax(cycle: 3, settings: s) == 115)
    }

    @Test func roundsToNearestIncrement() {
        #expect(StrengthMath.round(76.375, to: 2.5) == 77.5)
        #expect(StrengthMath.round(76.2, to: 2.5) == 75)
        #expect(StrengthMath.round(151.3, to: 5) == 150)
        #expect(StrengthMath.round(101.1, to: 1.25) == 101.25)
    }

    @Test func warmupsSkippedOnDeload() {
        let s = settings(warmups: true)
        let week1 = FiveThreeOne.prescription(session: 0, settings: s)
        #expect(week1.sets.filter { $0.kind == .warmup }.map(\.weight) == [40, 50, 60])
        #expect(week1.sets.filter { $0.kind == .warmup }.map(\.reps) == [5, 5, 3])
        let deload = FiveThreeOne.prescription(session: 3, settings: s)
        #expect(deload.header.isDeload)
        #expect(deload.sets.allSatisfy { $0.kind == .main })
    }

    @Test func fivesProHasNoAMRAP() {
        let s = settings(style: .fivesPro)
        #expect(main(FiveThreeOne.prescription(session: 2, settings: s)) == ["75x5", "85x5", "95x5"])
    }

    @Test func supplementalTemplates() {
        let fsl = FiveThreeOne.prescription(session: 1, settings: settings(supplemental: .firstSetLast))
        let fslSets = fsl.sets.filter { $0.kind == .supplemental }
        #expect(fslSets.count == 5)
        #expect(fslSets.allSatisfy { $0.weight == 70 && $0.reps == 5 })

        let bbb = FiveThreeOne.prescription(session: 0, settings: settings(supplemental: .boringButBig))
        let bbbSets = bbb.sets.filter { $0.kind == .supplemental }
        #expect(bbbSets.count == 5)
        #expect(bbbSets.allSatisfy { $0.weight == 50 && $0.reps == 10 })

        let deload = FiveThreeOne.prescription(session: 3, settings: settings(supplemental: .boringButBig))
        #expect(deload.sets.filter { $0.kind == .supplemental }.isEmpty)
    }

    @Test func noDeloadMakesThreeWeekCycles() {
        let s = settings(deload: false)
        let p = FiveThreeOne.prescription(session: 3, settings: s)
        #expect(p.header.cycle == 1)
        #expect(p.header.week == 0)
        #expect(p.header.trainingMax == 105)
    }

    @Test func perTrainingWeekRepeatsWeekForEachSession() {
        let s = settings(perWeek: 3)
        let headers = (0..<7).map { FiveThreeOne.prescription(session: $0, settings: s).header }
        #expect(headers.map(\.week) == [0, 0, 0, 1, 1, 1, 2])
        #expect(headers.map(\.dayInWeek) == [0, 1, 2, 0, 1, 2, 0])
        #expect(headers[1].subtitle == "Cycle 1 · Day 2 of 3")
        #expect(FiveThreeOne.prescription(session: 12, settings: s).header.cycle == 1)
    }

    @Test func changingFrequencyMidWeekStartsAtNextWeek() {
        var s = settings(perWeek: 3)
        // Session 4 is week 2, day 2 → the new 2x/week pattern starts at session 6 (week 3).
        s.segments = FiveThreeOne.segments(changingSessionsPerWeekTo: 2, effectiveFromSession: 4, settings: s)
        let weeks = (0..<10).map { FiveThreeOne.position(session: $0, settings: s).programWeek }
        #expect(weeks == [0, 0, 0, 1, 1, 1, 2, 2, 3, 3])
    }

    @Test func trainingMaxAdjustmentAppliesForward() {
        var s = settings()
        s.trainingMaxAdjustments = FiveThreeOne.adjustments(settingTrainingMax: 95, fromCycle: 2, date: .now, settings: s)
        #expect(FiveThreeOne.trainingMax(cycle: 1, settings: s) == 105)
        #expect(FiveThreeOne.trainingMax(cycle: 2, settings: s) == 95)
        #expect(FiveThreeOne.trainingMax(cycle: 3, settings: s) == 100)
    }

    @Test func oneRepMaxMath() {
        #expect(FiveThreeOne.trainingMax(fromOneRepMax: 140, percent: 0.9, rounding: 2.5) == 125)
        #expect(StrengthMath.estimatedOneRepMax(weight: 100, reps: 5) == 116.65)
        #expect(StrengthMath.estimatedOneRepMax(weight: 100, reps: 1) == 100)
        #expect(StrengthMath.estimatedOneRepMax(weight: 100, reps: 0) == 0)
    }

    @Test func plateLoadout() {
        let loadout = PlateCalculator.loadout(for: 102.5, unit: .kg)
        #expect(loadout?.perSide == [25, 15, 1.25])
        #expect(loadout?.remainder == 0)
        #expect(PlateCalculator.loadout(for: 20, unit: .kg)?.perSide == [])
        #expect(PlateCalculator.loadout(for: 15, unit: .kg) == nil)
        #expect(PlateCalculator.loadout(for: 225, unit: .lb)?.perSide == [45, 45])
    }

    @Test func weightFormatting() {
        #expect(WeightFormat.plain(102.5) == "102.5")
        #expect(WeightFormat.plain(100) == "100")
        #expect(WeightFormat.plain(1.25) == "1.25")
    }
}
