import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case json

    var id: String { rawValue }
    var name: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

struct ExportOptions: Hashable, Sendable {
    var includePlanned = false
}

struct ExportDocument: Codable {
    struct Account: Codable {
        var provider: String
        var email: String?
        var name: String?
    }

    struct ProgramEntry: Codable {
        var id: UUID
        var name: String
        var type: String
        var lift: String
        var unit: String
        var createdAt: Date
        var startDate: String
        var archived: Bool
        var sessionsPerWeek: Int
        var workoutDays: [String]
        var fiveThreeOne: FiveThreeOneSettings?
        var workouts: [WorkoutEntry]
    }

    struct WorkoutEntry: Codable {
        var id: UUID
        var session: Int
        var scheduledDate: String
        var status: String
        var startedAt: Date?
        var completedAt: Date?
        var missed: Bool
        /// 1-based.
        var cycle: Int?
        /// 1-based.
        var week: Int?
        var title: String?
        var trainingMax: Double?
        var notes: String?
        var sets: [SetEntry]
        var accessories: [AccessoryEntry]
    }

    struct SetEntry: Codable {
        var type: String
        var number: Int
        var targetWeight: Double
        var targetReps: Int
        var amrap: Bool
        var percentOfTrainingMax: Double?
        var weight: Double?
        var reps: Int?
        var completed: Bool
    }

    struct AccessoryEntry: Codable {
        var name: String
        var sets: [AccessorySetEntry]
    }

    struct AccessorySetEntry: Codable {
        var number: Int
        var weight: Double
        var reps: Int
        var completed: Bool
    }

    var format = "squats-export"
    var version = 1
    var exportedAt: Date
    var account: Account?
    var programs: [ProgramEntry]
}

enum Exporter {
    static func makeDocument(
        programs: [Program],
        workouts: [Workout],
        account: UserAccount?,
        options: ExportOptions,
        exportedAt: Date = .now,
        calendar: Calendar = .current
    ) -> ExportDocument {
        let day = dayFormatter(calendar)
        let entries = programs.sorted { $0.createdAt < $1.createdAt }.map { program in
            let programWorkouts = workouts
                .filter { $0.programID == program.id && (options.includePlanned || $0.status != .planned) }
                .sorted { ($0.scheduledDate, $0.sessionIndex) < ($1.scheduledDate, $1.sessionIndex) }
            return ExportDocument.ProgramEntry(
                id: program.id,
                name: program.name,
                type: program.kind.fullName,
                lift: program.liftName,
                unit: program.unit.symbol,
                createdAt: program.createdAt,
                startDate: day.string(from: program.startDate),
                archived: program.isArchived,
                sessionsPerWeek: program.schedule.sessionsPerWeek,
                workoutDays: program.schedule.orderedWeekdays(calendar).map { calendar.weekdaySymbols[$0 - 1] },
                fiveThreeOne: program.fiveThreeOne,
                workouts: programWorkouts.map { entry(for: $0, program: program, day: day) }
            )
        }
        let accountEntry = account.map {
            ExportDocument.Account(provider: $0.provider.rawValue, email: $0.email, name: $0.name)
        }
        return ExportDocument(exportedAt: exportedAt, account: accountEntry, programs: entries)
    }

    private static func entry(for workout: Workout, program: Program, day: DateFormatter) -> ExportDocument.WorkoutEntry {
        let header = workout.header
            ?? (workout.status == .planned ? ProgramEngine.prescription(for: program, sessionIndex: workout.sessionIndex).header : nil)

        var sets: [ExportDocument.SetEntry] = []
        var counters: [SetKind: Int] = [:]
        if workout.status == .planned {
            for set in ProgramEngine.prescription(for: program, sessionIndex: workout.sessionIndex).sets {
                counters[set.kind, default: 0] += 1
                sets.append(.init(type: set.kind.rawValue, number: counters[set.kind]!, targetWeight: set.weight,
                                  targetReps: set.reps, amrap: set.isAMRAP, percentOfTrainingMax: set.percentOfTM,
                                  weight: nil, reps: nil, completed: false))
            }
        } else {
            for set in workout.sets {
                counters[set.kind, default: 0] += 1
                sets.append(.init(type: set.kind.rawValue, number: counters[set.kind]!, targetWeight: set.targetWeight,
                                  targetReps: set.targetReps, amrap: set.isAMRAP, percentOfTrainingMax: set.percentOfTM,
                                  weight: set.weight, reps: set.reps, completed: set.isCompleted))
            }
        }

        let accessories = workout.accessories.map { accessory in
            ExportDocument.AccessoryEntry(
                name: accessory.name,
                sets: accessory.sets.enumerated().map { index, set in
                    .init(number: index + 1, weight: set.weight, reps: set.reps, completed: set.isCompleted)
                }
            )
        }

        return ExportDocument.WorkoutEntry(
            id: workout.id,
            session: workout.sessionIndex + 1,
            scheduledDate: day.string(from: workout.scheduledDate),
            status: workout.status.rawValue,
            startedAt: workout.startedAt,
            completedAt: workout.completedAt,
            missed: workout.missedOn != nil,
            cycle: header.map { $0.cycle + 1 },
            week: header.map { $0.week + 1 },
            title: header?.title,
            trainingMax: header?.trainingMax,
            notes: workout.notes.isEmpty ? nil : workout.notes,
            sets: sets,
            accessories: accessories
        )
    }

    // MARK: JSON

    static func json(_ document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    // MARK: CSV

    static let csvColumns = [
        "program", "program_id", "workout_id", "scheduled_date", "status", "started_at", "completed_at", "missed",
        "cycle", "week", "session", "training_max", "exercise", "set_type", "set_number",
        "target_weight", "target_reps", "amrap", "percent_of_tm", "weight", "reps", "completed", "unit", "notes",
    ]

    /// One row per set (main lift and accessories). Workouts with no sets still get one row.
    static func csv(_ document: ExportDocument, timeZone: TimeZone = .current) -> String {
        let timestamp = ISO8601DateFormatter()
        timestamp.timeZone = timeZone
        func time(_ date: Date?) -> String { date.map(timestamp.string(from:)) ?? "" }
        func number(_ value: Double?) -> String { value.map(WeightFormat.plain) ?? "" }
        func int(_ value: Int?) -> String { value.map(String.init) ?? "" }

        var lines = [csvColumns.joined(separator: ",")]
        for program in document.programs {
            for workout in program.workouts {
                let base = [
                    program.name, program.id.uuidString, workout.id.uuidString, workout.scheduledDate, workout.status,
                    time(workout.startedAt), time(workout.completedAt), workout.missed ? "true" : "false",
                    int(workout.cycle), int(workout.week), workout.title ?? "", number(workout.trainingMax),
                ]
                var rows: [[String]] = []
                for set in workout.sets {
                    rows.append([
                        program.lift, set.type, String(set.number), number(set.targetWeight), String(set.targetReps),
                        set.amrap ? "true" : "false", number(set.percentOfTrainingMax.map { $0 * 100 }),
                        number(set.weight), int(set.reps), set.completed ? "true" : "false",
                    ])
                }
                for accessory in workout.accessories {
                    for set in accessory.sets {
                        rows.append([
                            accessory.name, "accessory", String(set.number), "", "", "false", "",
                            number(set.weight), String(set.reps), set.completed ? "true" : "false",
                        ])
                    }
                }
                if rows.isEmpty { rows.append(Array(repeating: "", count: 10)) }
                for row in rows {
                    lines.append((base + row + [program.unit, workout.notes ?? ""]).map(escape).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Files

    /// Writes the export to a temporary file ready for the share sheet.
    static func writeFile(_ document: ExportDocument, format: ExportFormat, calendar: Calendar = .current) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "squats-export-\(dayFormatter(calendar).string(from: document.exportedAt)).\(format.fileExtension)"
        let url = directory.appendingPathComponent(name)
        let data: Data
        switch format {
        case .json: data = try json(document)
        case .csv: data = Data(csv(document, timeZone: calendar.timeZone).utf8)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
