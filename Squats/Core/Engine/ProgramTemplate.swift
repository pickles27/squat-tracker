import Foundation

/// How many training days per week a program allows.
enum DayRequirement: Codable, Hashable, Sendable {
    case exactly(Int)
    case range(Int, Int)

    var bounds: ClosedRange<Int> {
        switch self {
        case .exactly(let count): count...count
        case .range(let low, let high): min(low, high)...max(low, high)
        }
    }

    func allows(_ count: Int) -> Bool { bounds.contains(count) }

    var description: String {
        switch self {
        case .exactly(let count): "\(count) day\(count == 1 ? "" : "s") a week"
        case .range(let low, let high): "\(low)–\(high) days a week"
        }
    }
}

enum WeekKind: String, Codable, Sendable {
    case training
    /// Training-max test week (5/3/1).
    case test
    case deload
}

struct TemplateLift: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var isLowerBody: Bool
}

/// One prescribed set as a percentage of the lift's training max.
struct SetScheme: Codable, Hashable, Sendable {
    var kind: SetKind
    var percent: Double
    var reps: Int
    var isAMRAP = false
    var maxReps: Int?
}

struct LiftWork: Codable, Hashable, Sendable {
    var liftID: String
    var sets: [SetScheme]
}

struct TemplateDay: Codable, Hashable, Sendable {
    var lifts: [LiftWork]
}

struct TemplateWeek: Codable, Hashable, Sendable {
    var name: String
    var kind: WeekKind
    /// 0-based cycle within the block; nil for weeks that sit between cycles (TM test, deload).
    var cycleInBlock: Int?
    /// Training maxes go up by each lift's increment once this week is over.
    var increasesTrainingMaxAfter: Bool
    var days: [TemplateDay]
}

/// Data-driven program definition. Built-in programs and (later) custom programs share this format.
/// `weeks` is a block that repeats forever; every week has the same number of days.
struct ProgramTemplate: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
    var isBuiltIn: Bool
    var dayRequirement: DayRequirement
    /// Share of the estimated 1RM used as the starting training max.
    var trainingMaxPercent: Double
    var lifts: [TemplateLift]
    var weeks: [TemplateWeek]

    var daysPerWeek: Int { weeks.first?.days.count ?? 0 }

    var cyclesPerBlock: Int { (weeks.compactMap(\.cycleInBlock).max() ?? -1) + 1 }

    var isValid: Bool {
        !weeks.isEmpty && daysPerWeek > 0
            && weeks.allSatisfy { $0.days.count == daysPerWeek }
            && dayRequirement.allows(daysPerWeek)
    }

    func lift(_ id: String) -> TemplateLift? {
        lifts.first { $0.id == id }
    }
}
