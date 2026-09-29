import SwiftUI

@main
struct SquatsApp: App {
    @State private var auth = AuthManager()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
