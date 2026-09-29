import Foundation

struct PrescribedSet: Hashable, Sendable {
    var liftID: String
    var liftName: String
    var kind: SetKind
    var weight: Double
    var reps: Int
    var isAMRAP: Bool
    var maxReps: Int?
    var percentOfTM: Double?
}

struct SessionPrescription: Hashable, Sendable {
    var header: SessionHeader
    var sets: [PrescribedSet]

    /// Lift IDs in the order they're performed.
    var liftIDs: [String] {
        var seen = Set<String>()
        return sets.map(\.liftID).filter { seen.insert($0).inserted }
    }

    func sets(for liftID: String) -> [PrescribedSet] {
        sets.filter { $0.liftID == liftID }
    }

    /// The heaviest main set of a lift (the AMRAP set in 5/3/1).
    func topSet(for liftID: String) -> PrescribedSet? {
        sets.last { $0.liftID == liftID && $0.kind == .main }
    }
}

struct ProgramPosition: Hashable, Sendable {
    var programWeek: Int
    var block: Int
    var blockWeek: Int
    var dayInWeek: Int
    var daysInWeek: Int
    var cycle: Int?
}

/// Suggested training-max change after a failed TM test or a stalled cycle.
struct TrainingMaxSuggestion: Hashable, Identifiable, Sendable {
    enum Reason: String, Hashable, Sendable {
        case failedTest
        case stalled
    }

    var liftID: String
    var liftName: String
    var reason: Reason
    var currentTrainingMax: Double
    var suggestedTrainingMax: Double
    var fromProgramWeek: Int
    var explanation: String

    var id: String { "\(liftID)-\(reason.rawValue)-\(fromProgramWeek)" }
}

/// Turns a program's template + lifts into concrete sessions.
enum ProgramEngine {
    static func position(session: Int, template: ProgramTemplate) -> ProgramPosition {
        let daysPerWeek = max(1, template.daysPerWeek)
        let blockLength = max(1, template.weeks.count)
        let session = max(0, session)
        let programWeek = session / daysPerWeek
        let blockWeek = programWeek % blockLength
        let block = programWeek / blockLength
        let cycle = template.weeks.indices.contains(blockWeek)
            ? template.weeks[blockWeek].cycleInBlock.map { block * template.cyclesPerBlock + $0 }
            : nil
        return ProgramPosition(programWeek: programWeek, block: block, blockWeek: blockWeek,
                               dayInWeek: session % daysPerWeek, daysInWeek: daysPerWeek, cycle: cycle)
    }

    static func week(at programWeek: Int, template: ProgramTemplate) -> TemplateWeek? {
        guard !template.weeks.isEmpty else { return nil }
        return template.weeks[programWeek % template.weeks.count]
    }

    /// How many training-max increases have happened before `programWeek` starts.
    static func increaseCount(before programWeek: Int, template: ProgramTemplate) -> Int {
        let blockLength = template.weeks.count
        guard blockLength > 0, programWeek > 0 else { return 0 }
        let perBlock = template.weeks.filter(\.increasesTrainingMaxAfter).count
        let block = programWeek / blockLength
        let blockWeek = programWeek % blockLength
        return block * perBlock + template.weeks.prefix(blockWeek).filter(\.increasesTrainingMaxAfter).count
    }

    static func trainingMax(liftID: String, programWeek: Int, program: Program) -> Double {
        guard let lift = program.lift(liftID) else { return 0 }
        let steps = increaseCount(before: programWeek, template: program.template)
        if let adjustment = program.trainingMaxAdjustments.last(where: { $0.liftID == liftID && $0.fromProgramWeek <= programWeek }) {
            let since = steps - increaseCount(before: adjustment.fromProgramWeek, template: program.template)
            return StrengthMath.clean(adjustment.trainingMax + Double(since) * lift.increment)
        }
        return StrengthMath.clean(lift.startingTrainingMax + Double(steps) * lift.increment)
    }

    static func prescription(for program: Program, session: Int) -> SessionPrescription {
        let template = program.template
        let position = position(session: session, template: template)
        let week = week(at: position.programWeek, template: template)
        let day = week.flatMap { $0.days.indices.contains(position.dayInWeek) ? $0.days[position.dayInWeek] : nil }

        var sets: [PrescribedSet] = []
        var trainingMaxes: [String: Double] = [:]
        var liftNames: [String] = []
        for work in day?.lifts ?? [] {
            let trainingMax = trainingMax(liftID: work.liftID, programWeek: position.programWeek, program: program)
            let name = program.lift(work.liftID)?.name ?? template.lift(work.liftID)?.name ?? work.liftID
            trainingMaxes[work.liftID] = trainingMax
            liftNames.append(name)
            for scheme in work.sets {
                sets.append(PrescribedSet(
                    liftID: work.liftID,
                    liftName: name,
                    kind: scheme.kind,
                    weight: StrengthMath.round(trainingMax * scheme.percent, to: program.rounding),
                    reps: scheme.reps,
                    isAMRAP: scheme.isAMRAP,
                    maxReps: scheme.maxReps,
                    percentOfTM: scheme.percent
                ))
            }
        }

        let dayText = "Day \(position.dayInWeek + 1) of \(position.daysInWeek)"
        let subtitle = position.cycle.map { "Cycle \($0 + 1) · \(dayText)" } ?? dayText
        let header = SessionHeader(
            title: week?.name ?? "Workout",
            subtitle: subtitle,
            programWeek: position.programWeek,
            cycle: position.cycle,
            weekKind: week?.kind ?? .training,
            dayInWeek: position.dayInWeek,
            daysInWeek: position.daysInWeek,
            liftNames: liftNames,
            trainingMaxes: trainingMaxes
        )
        return SessionPrescription(header: header, sets: sets)
    }

    /// True when finishing this session completes a cycle (training maxes go up next week).
    static func completesCycle(_ header: SessionHeader, template: ProgramTemplate) -> Bool {
        guard let week = week(at: header.programWeek, template: template) else { return false }
        return week.increasesTrainingMaxAfter && header.dayInWeek == header.daysInWeek - 1
    }
}
