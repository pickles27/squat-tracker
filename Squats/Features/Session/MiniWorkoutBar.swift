import SwiftUI

/// Minimized in-progress workout(s), shown above the tab bar. Tapping expands workout mode.
/// PLACEHOLDER: owned by the Workout Mode workstream.
struct MiniWorkoutBar: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(SessionCoordinator.self) private var session

    var body: some View {
        if let workout = store.inProgressWorkouts.last {
            Button("Resume workout") { session.open(workout.id) }
                .buttonStyle(.borderedProminent)
        }
    }
}
