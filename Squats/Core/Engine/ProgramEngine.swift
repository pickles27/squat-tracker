import Foundation

struct PrescribedSet: Hashable, Sendable {
    var kind: SetKind
    var weight: Double
    var reps: Int
    var isAMRAP: Bool
    var percentOfTM: Double?
}

struct SessionPrescription: Hashable, Sendable {
    var header: SessionHeader
    var sets: [PrescribedSet]

    /// The heaviest main set (the AMRAP set in standard 5/3/1).
    var topSet: PrescribedSet? { sets.last { $0.kind == .main } }
}

/// Dispatches to the engine for each program kind.
enum ProgramEngine {
    static func prescription(for program: Program, sessionIndex: Int) -> SessionPrescription {
        switch program.kind {
        case .fiveThreeOne:
            FiveThreeOne.prescription(session: sessionIndex, settings: settings(for: program))
        }
    }

    /// If finishing a session with this header completes a cycle, returns that cycle and the next training max.
    static func cycleCompletion(for program: Program, header: SessionHeader) -> (cycle: Int, nextTrainingMax: Double)? {
        switch program.kind {
        case .fiveThreeOne:
            let settings = settings(for: program)
            let lastWeek = FiveThreeOne.weeksPerCycle(settings) - 1
            guard header.week == lastWeek, header.dayInWeek == header.sessionsInWeek - 1 else { return nil }
            return (header.cycle, FiveThreeOne.trainingMax(cycle: header.cycle + 1, settings: settings))
        }
    }

    static func weeksPerCycle(for program: Program) -> Int {
        switch program.kind {
        case .fiveThreeOne: FiveThreeOne.weeksPerCycle(settings(for: program))
        }
    }

    static func trainingMax(for program: Program, cycle: Int) -> Double {
        switch program.kind {
        case .fiveThreeOne: FiveThreeOne.trainingMax(cycle: cycle, settings: settings(for: program))
        }
    }

    private static func settings(for program: Program) -> FiveThreeOneSettings {
        program.fiveThreeOne ?? FiveThreeOneSettings(
            startingTrainingMax: 0,
            cycleIncrement: program.unit.defaultCycleIncrement,
            rounding: program.unit.defaultRounding,
            sessionsPerWeek: program.schedule.sessionsPerWeek
        )
    }
}
