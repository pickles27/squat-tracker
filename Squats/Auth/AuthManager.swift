import AuthenticationServices
import Foundation
import Observation
import SwiftUI

/// Signed-in account and Google tokens. PLACEHOLDER: owned by the Auth & Sync workstream.
@MainActor
@Observable
final class AuthManager {
    private(set) var currentUser: UserAccount?
    var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let userDefaultsKey = "auth.currentUser"

    init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let user = try? JSONDecoder().decode(UserAccount.self, from: data) {
            currentUser = user
        }
    }

    var isGoogleConfigured: Bool { AppConfig.google.isValid }

    /// Runs the Google OAuth (PKCE) flow in a browser sheet and signs in.
    func signInWithGoogle(using session: WebAuthenticationSession) async {
        errorMessage = OAuthError.notConfigured.localizedDescription
    }

    /// On-device account for development and trying the app before Google is set up.
    func signInLocally() {
        setUser(UserAccount(provider: .local, subject: "local-device", name: "Local Athlete"))
    }

    func signOut() async {
        setUser(nil)
    }

    /// A valid Google access token for Drive (refreshed when needed). Throws if not signed in with Google.
    func accessToken() async throws -> String {
        throw OAuthError.notConfigured
    }

    private func setUser(_ user: UserAccount?) {
        currentUser = user
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }
}
