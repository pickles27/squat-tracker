import SwiftUI

enum AppTab: Hashable {
    case home, calendar, settings
}

struct MainTabView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(SyncManager.self) private var sync
    @Environment(SessionCoordinator.self) private var session
    @State private var selection: AppTab = .home

    var body: some View {
        @Bindable var session = session
        TabView(selection: $selection) {
            HomeView()
                .miniWorkoutBarInset()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            CalendarTab()
                .miniWorkoutBarInset()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            SettingsView()
                .miniWorkoutBarInset()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: $session.isExpanded) {
            WorkoutSessionView()
                .environment(store)
                .environment(sync)
                .environment(session)
        }
    }
}

private struct MiniWorkoutBarInset: ViewModifier {
    @Environment(WorkoutStore.self) private var store
    @Environment(SessionCoordinator.self) private var session

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.inProgressWorkouts.isEmpty && !session.isExpanded {
                MiniWorkoutBar()
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    /// Shows the minimized in-progress workout bar above the tab bar.
    func miniWorkoutBarInset() -> some View {
        modifier(MiniWorkoutBarInset())
    }
}
