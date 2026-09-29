import SwiftUI

/// Settings row showing backup status with a "Sync now" action.
/// PLACEHOLDER: owned by the Auth & Sync workstream; used by Settings.
struct SyncStatusView: View {
    @Environment(SyncManager.self) private var sync

    var body: some View {
        LabeledContent("Backup", value: "\(sync.status)")
    }
}
