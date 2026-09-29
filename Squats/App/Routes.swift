import SwiftUI

/// Navigation destinations shared by every tab's NavigationStack.
enum Route: Hashable {
    case program(UUID)
    case workout(UUID)
}

extension View {
    /// Registers the app's navigation destinations. Apply once inside each NavigationStack.
    func appNavigationDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .program(let id): ProgramDetailView(programID: id)
            case .workout(let id): WorkoutDetailView(workoutID: id)
            }
        }
    }
}
