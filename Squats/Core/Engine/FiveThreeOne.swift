import Foundation

enum MainSetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case fivesPro

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: "Standard"
        case .fivesPro: "5s PRO"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Last set is AMRAP: 5+, 3+, 1+"
        case .fivesPro: "Every set is ×5, no AMRAP"
        }
    }
}

enum SupplementalTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case firstSetLast
    case boringButBig

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: "None"
        case .firstSetLast: "First Set Last"
        case .boringButBig: "Boring But Big"
        }
    }

    var detail: String {
        switch self {
        case .none: "Just the main sets"
        case .firstSetLast: "5×5 at the first working set's weight"
        case .boringButBig: "5×10 at a light % of your training max"
        }
    }
}

/// When the program moves on to the next 5/3/1 week.
enum AdvanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// All workouts in a calendar week share that week's percentages (classic 5/3/1 pacing: +TM every ~4 weeks).
    case perTrainingWeek
    /// Every workout is the next week of the cycle (faster: a cycle lasts four workouts).
    case perWorkout

    var id: String { rawValue }

    var name: String {
        switch self {
        case .perTrainingWeek: "Once per week"
        case .perWorkout: "Every workout"
        }
    }
}

/// Maps session indices to program weeks. A new segment starts whenever the number of
/// sessions per program week changes, so past sessions keep their week numbers.
struct ProgressionSegment: Codable, Hashable, Sendable {
    var fromSession: Int
    var fromProgramWeek: Int
    var sessionsPerProgramWeek: Int
}

/// Manual training-max change that applies from `fromCycle` onward.
struct TrainingMaxAdjustment: Codable, Hashable, Sendable {
    var fromCycle: Int
    var trainingMax: Double
    var date: Date
}

struct FiveThreeOneSettings: Codable, Hashable, Sendable {
    var startingTrainingMax: Double
    var trainingMaxPercent: Double
    var enteredOneRepMax: Double?
    var cycleIncrement: Double
    var rounding: Double
    var includeWarmups: Bool
    var includeDeload: Bool
    var mainSetStyle: MainSetStyle
    var supplemental: SupplementalTemplate
    var bbbPercent: Double
    var advanceMode: AdvanceMode
    var segments: [ProgressionSegment]
    var trainingMaxAdjustments: [TrainingMaxAdjustment]

    init(
        startingTrainingMax: Double,
        trainingMaxPercent: Double = 0.9,
        enteredOneRepMax: Double? = nil,
        cycleIncrement: Double,
        rounding: Double,
        includeWarmups: Bool = true,
        includeDeload: Bool = true,
        mainSetStyle: MainSetStyle = .standard,
        supplemental: SupplementalTemplate = .none,
        bbbPercent: Double = 0.5,
        advanceMode: AdvanceMode = .perTrainingWeek,
        sessionsPerWeek: Int
    ) {
        self.startingTrainingMax = startingTrainingMax
        self.trainingMaxPercent = trainingMaxPercent
        self.enteredOneRepMax = enteredOneRepMax
        self.cycleIncrement = cycleIncrement
        self.rounding = rounding
        self.includeWarmups = includeWarmups
        self.includeDeload = includeDeload
        self.mainSetStyle = mainSetStyle
        self.supplemental = supplemental
        self.bbbPercent = bbbPercent
        self.advanceMode = advanceMode
        let perWeek = advanceMode == .perWorkout ? 1 : max(1, sessionsPerWeek)
        self.segments = [ProgressionSegment(fromSession: 0, fromProgramWeek: 0, sessionsPerProgramWeek: perWeek)]
        self.trainingMaxAdjustments = []
    }
}

struct SchemeSet: Hashable, Sendable {
    var percent: Double
    var reps: Int
    var isAMRAP: Bool
}

struct FiveThreeOnePosition: Hashable, Sendable {
    /// 0-based week counted from the start of the program.
    var programWeek: Int
    var cycle: Int
    var week: Int
    var dayInWeek: Int
    var sessionsInWeek: Int
}

/// Jim Wendler's 5/3/1: percentages of a training max (TM ≈ 90% of 1RM).
enum FiveThreeOne {
    static let weekNames = ["5s", "3s", "5/3/1", "Deload"]

    static let warmupScheme = [
        SchemeSet(percent: 0.40, reps: 5, isAMRAP: false),
        SchemeSet(percent: 0.50, reps: 5, isAMRAP: false),
        SchemeSet(percent: 0.60, reps: 3, isAMRAP: false),
    ]

    static func mainScheme(week: Int, style: MainSetStyle) -> [SchemeSet] {
        let base: [(percent: Double, reps: Int)]
        switch week {
        case 0: base = [(0.65, 5), (0.75, 5), (0.85, 5)]
        case 1: base = [(0.70, 3), (0.80, 3), (0.90, 3)]
        case 2: base = [(0.75, 5), (0.85, 3), (0.95, 1)]
        default:
            return [(0.40, 5), (0.50, 5), (0.60, 5)].map { SchemeSet(percent: $0.0, reps: $0.1, isAMRAP: false) }
        }
        return base.enumerated().map { index, set in
            switch style {
            case .standard: SchemeSet(percent: set.percent, reps: set.reps, isAMRAP: index == base.count - 1)
            case .fivesPro: SchemeSet(percent: set.percent, reps: 5, isAMRAP: false)
            }
        }
    }

    static func weeksPerCycle(_ settings: FiveThreeOneSettings) -> Int {
        settings.includeDeload ? 4 : 3
    }

    static func position(session: Int, settings: FiveThreeOneSettings) -> FiveThreeOnePosition {
        let session = max(0, session)
        let segment = settings.segments.last { $0.fromSession <= session }
            ?? ProgressionSegment(fromSession: 0, fromProgramWeek: 0, sessionsPerProgramWeek: 1)
        let perWeek = max(1, segment.sessionsPerProgramWeek)
        let offset = session - segment.fromSession
        let programWeek = segment.fromProgramWeek + offset / perWeek
        let weeks = weeksPerCycle(settings)
        return FiveThreeOnePosition(
            programWeek: programWeek,
            cycle: programWeek / weeks,
            week: programWeek % weeks,
            dayInWeek: offset % perWeek,
            sessionsInWeek: perWeek
        )
    }

    static func trainingMax(cycle: Int, settings: FiveThreeOneSettings) -> Double {
        if let adjustment = settings.trainingMaxAdjustments.last(where: { $0.fromCycle <= cycle }) {
            return StrengthMath.clean(adjustment.trainingMax + Double(cycle - adjustment.fromCycle) * settings.cycleIncrement)
        }
        return StrengthMath.clean(settings.startingTrainingMax + Double(cycle) * settings.cycleIncrement)
    }

    static func trainingMax(fromOneRepMax oneRepMax: Double, percent: Double, rounding: Double) -> Double {
        StrengthMath.round(oneRepMax * percent, to: rounding)
    }

    static func isDeload(week: Int, settings: FiveThreeOneSettings) -> Bool {
        settings.includeDeload && week == 3
    }

    static func prescription(session: Int, settings: FiveThreeOneSettings) -> SessionPrescription {
        let position = position(session: session, settings: settings)
        let trainingMax = trainingMax(cycle: position.cycle, settings: settings)
        let deload = isDeload(week: position.week, settings: settings)
        var sets: [PrescribedSet] = []

        func add(_ kind: SetKind, _ scheme: SchemeSet) {
            sets.append(PrescribedSet(
                kind: kind,
                weight: StrengthMath.round(trainingMax * scheme.percent, to: settings.rounding),
                reps: scheme.reps,
                isAMRAP: scheme.isAMRAP,
                percentOfTM: scheme.percent
            ))
        }

        // The deload week *is* the warm-up percentages, so it gets no separate warm-up or supplemental work.
        if settings.includeWarmups && !deload {
            warmupScheme.forEach { add(.warmup, $0) }
        }
        let main = mainScheme(week: position.week, style: settings.mainSetStyle)
        main.forEach { add(.main, $0) }
        if !deload {
            switch settings.supplemental {
            case .none:
                break
            case .firstSetLast:
                for _ in 0..<5 { add(.supplemental, SchemeSet(percent: main[0].percent, reps: 5, isAMRAP: false)) }
            case .boringButBig:
                for _ in 0..<5 { add(.supplemental, SchemeSet(percent: settings.bbbPercent, reps: 10, isAMRAP: false)) }
            }
        }

        var subtitle = "Cycle \(position.cycle + 1)"
        if position.sessionsInWeek > 1 {
            subtitle += " · Day \(position.dayInWeek + 1) of \(position.sessionsInWeek)"
        }
        let header = SessionHeader(
            title: "Week \(position.week + 1) · \(weekNames[position.week])",
            subtitle: subtitle,
            cycle: position.cycle,
            week: position.week,
            dayInWeek: position.dayInWeek,
            sessionsInWeek: position.sessionsInWeek,
            trainingMax: trainingMax,
            isDeload: deload
        )
        return SessionPrescription(header: header, sets: sets)
    }

    /// New segment list after the weekly session count changes. The change takes effect at the start
    /// of the next program week so the current week keeps its shape and past sessions never move.
    static func segments(
        changingSessionsPerWeekTo newPerWeek: Int,
        effectiveFromSession session: Int,
        settings: FiveThreeOneSettings
    ) -> [ProgressionSegment] {
        guard settings.advanceMode == .perTrainingWeek else { return settings.segments }
        let position = position(session: session, settings: settings)
        guard position.sessionsInWeek != newPerWeek else { return settings.segments }
        let from: Int
        let fromWeek: Int
        if position.dayInWeek == 0 {
            from = session
            fromWeek = position.programWeek
        } else {
            from = session + (position.sessionsInWeek - position.dayInWeek)
            fromWeek = position.programWeek + 1
        }
        var result = settings.segments.filter { $0.fromSession < from }
        result.append(ProgressionSegment(fromSession: from, fromProgramWeek: fromWeek, sessionsPerProgramWeek: max(1, newPerWeek)))
        return result
    }

    /// Adjustment list after setting a new training max from `cycle` onward (replaces later adjustments).
    static func adjustments(
        settingTrainingMax trainingMax: Double,
        fromCycle cycle: Int,
        date: Date,
        settings: FiveThreeOneSettings
    ) -> [TrainingMaxAdjustment] {
        var result = settings.trainingMaxAdjustments.filter { $0.fromCycle < cycle }
        result.append(TrainingMaxAdjustment(fromCycle: cycle, trainingMax: trainingMax, date: date))
        return result
    }
}
