import Foundation

/// Everything stored for one account. This is the file saved on the phone and the file synced to Google Drive.
struct AppData: Codable, Sendable {
    static let currentVersion = 2

    var version = AppData.currentVersion
    var programs: [Program] = []
    var workouts: [Workout] = []
    var exercises: [Exercise] = []
    /// Deleted record IDs, so a deletion on one device isn't undone by another device's older copy.
    var deletions: [Tombstone] = []
}

struct Tombstone: Codable, Hashable, Sendable {
    var id: UUID
    var deletedAt: Date
}

protocol SyncRecord: Identifiable where ID == UUID {
    var updatedAt: Date { get }
}

extension Program: SyncRecord {}
extension Workout: SyncRecord {}
extension Exercise: SyncRecord {}

/// Merges two copies of the data record by record: the newest `updatedAt` wins, and a deletion wins over
/// any version of the record that isn't newer than the deletion. Commutative, so either side can merge.
enum SyncMerge {
    static func merge(_ local: AppData, _ remote: AppData) -> AppData {
        var tombstones: [UUID: Date] = [:]
        for tombstone in local.deletions + remote.deletions {
            tombstones[tombstone.id] = max(tombstones[tombstone.id] ?? .distantPast, tombstone.deletedAt)
        }

        func records<T: SyncRecord>(_ lhs: [T], _ rhs: [T]) -> [T] {
            var newest: [UUID: T] = [:]
            var order: [UUID] = []
            for record in lhs + rhs {
                if let existing = newest[record.id] {
                    if record.updatedAt > existing.updatedAt { newest[record.id] = record }
                } else {
                    newest[record.id] = record
                    order.append(record.id)
                }
            }
            return order.compactMap { id in
                guard let record = newest[id] else { return nil }
                if let deletedAt = tombstones[id], deletedAt >= record.updatedAt { return nil }
                return record
            }
        }

        let programs = records(local.programs, remote.programs)
        let programIDs = Set(programs.map(\.id))
        return AppData(
            version: max(local.version, remote.version),
            programs: programs,
            workouts: records(local.workouts, remote.workouts).filter { programIDs.contains($0.programID) },
            exercises: records(local.exercises, remote.exercises),
            deletions: tombstones.map { Tombstone(id: $0.key, deletedAt: $0.value) }.sorted { $0.deletedAt < $1.deletedAt }
        )
    }
}
