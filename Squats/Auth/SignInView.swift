import AuthenticationServices
import SwiftUI

/// PLACEHOLDER: owned by the Auth & Sync workstream.
struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 16) {
            Text("Squat Tracker").font(.largeTitle.bold())
            Button("Continue with Google") {
                Task { await auth.signInWithGoogle(using: webAuthenticationSession) }
            }
            .buttonStyle(.borderedProminent)
            Button("Use a local account") { auth.signInLocally() }
            if let error = auth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
    }
}
