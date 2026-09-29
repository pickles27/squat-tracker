import SwiftUI

/// Settings tab. PLACEHOLDER: owned by the Calendar & Settings workstream.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        NavigationStack {
            Form {
                SyncStatusView()
                Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
            }
            .navigationTitle("Settings")
        }
    }
}
