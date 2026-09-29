import SwiftUI

/// Shows sign-in until there's an account, then that account's data.
struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if let user = auth.currentUser {
                SignedInRootView(user: user)
                    .id(user.id)
            } else {
                SignInView()
            }
        }
        .animation(.default, value: auth.currentUser?.id)
    }
}

/// Owns the per-account store, sync and workout-session state.
struct SignedInRootView: View {
    let user: UserAccount

    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: WorkoutStore?
    @State private var sync: SyncManager?
    @State private var session = SessionCoordinator()

    var body: some View {
        Group {
            if let store, let sync {
                MainTabView()
                    .environment(store)
                    .environment(sync)
                    .environment(session)
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: setUp)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store?.refresh()
                sync?.appDidBecomeActive()
            case .background:
                store?.saveNow()
            default:
                break
            }
        }
    }

    private func setUp() {
        guard store == nil else { return }
        let store = WorkoutStore(fileURL: AppPaths.dataFile(for: user))
        store.refresh()
        let sync = SyncManager(auth: auth, store: store)
        self.store = store
        self.sync = sync
        sync.start()
    }
}
