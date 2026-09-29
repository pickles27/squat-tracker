import CryptoKit
import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case push
    case pull
    case singleLegCore
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .singleLegCore: "Single Leg / Core"
        case .other: "Other"
        }
    }
}

/// An entry in the user's accessory exercise library.
struct Exercise: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var category: ExerciseCategory
    var isBuiltIn: Bool
    /// Built-ins are hidden rather than deleted so they can be restored.
    var isHidden = false
    var updatedAt: Date = .distantPast
}

enum StableID {
    /// Deterministic UUID for a key, so separate devices create identical IDs for the same thing.
    static func uuid(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Built-in accessories, from the 5/3/1 for Beginners assistance lists plus shoulder work to replace overhead press.
enum ExerciseCatalog {
    static let builtIns: [Exercise] = {
        let groups: [(ExerciseCategory, [String])] = [
            (.push, ["Dips", "Push-ups", "Flat DB Bench", "Incline DB Bench", "DB Overhead Press", "Arnold Press",
                     "Lateral Raises", "Tricep Extensions", "Tricep Pushdowns"]),
            (.pull, ["Chin-ups", "Pull-ups", "Inverted Rows", "DB Rows", "Cable Rows", "Machine Rows", "Face Pulls",
                     "Band Pull-Aparts", "Lat Pulldowns", "Curls"]),
            (.singleLegCore, ["Ab Wheel", "Hanging Leg Raises", "Planks", "Back Raises", "Reverse Hypers", "Lunges",
                              "Step-ups", "Bulgarian Split Squats", "KB Swings", "KB Snatches"]),
        ]
        return groups.flatMap { category, names in
            names.map { Exercise(id: StableID.uuid("builtin-exercise|\($0)"), name: $0, category: category, isBuiltIn: true) }
        }
    }()
}
