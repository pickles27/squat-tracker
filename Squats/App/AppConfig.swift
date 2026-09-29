import Foundation

enum AppConfig {
    /// iOS OAuth client ID from Google Cloud Console (see README → "Google sign-in and Drive backup").
    /// Looks like "1234567890-abc123.apps.googleusercontent.com".
    static let googleClientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"

    static var google: GoogleOAuthConfiguration { GoogleOAuthConfiguration(clientID: googleClientID) }
}

enum AppPaths {
    /// Each account gets its own data file: Application Support/Squats/Users/<hash>/data.json
    static func dataFile(for user: UserAccount) -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Squats", isDirectory: true)
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(user.storageKey, isDirectory: true)
            .appendingPathComponent("data.json")
    }
}
