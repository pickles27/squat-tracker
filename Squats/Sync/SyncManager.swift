import Foundation
import Observation

/// Backs up and syncs the store to the hidden app folder in the user's Google Drive.
/// PLACEHOLDER: owned by the Auth & Sync workstream.
@MainActor
@Observable
final class SyncManager {
    enum Status: Equatable {
        /// Not signed in with Google (e.g. local account): data stays on this device.
        case disabled
        case idle
        case syncing
        case upToDate
        case offline
        case failed(String)
    }

    private(set) var status: Status = .disabled
    private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let auth: AuthManager
    @ObservationIgnored private let store: WorkoutStore

    init(auth: AuthManager, store: WorkoutStore) {
        self.auth = auth
        self.store = store
    }

    /// Called once when the signed-in UI appears: pull + merge, then keep uploading after local saves.
    func start() {}

    func appDidBecomeActive() {}

    func syncNow() async {}
}
