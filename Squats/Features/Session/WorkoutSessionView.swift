import SwiftUI

/// Full-screen workout mode for `SessionCoordinator.focusedWorkoutID`.
/// PLACEHOLDER: owned by the Workout Mode workstream.
struct WorkoutSessionView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(SessionCoordinator.self) private var session

    var body: some View {
        NavigationStack {
            Text(store.workout(session.focusedWorkoutID).flatMap { store.header(for: $0)?.title } ?? "No workout")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Minimize", systemImage: "chevron.down") { session.minimize() }
                    }
                }
        }
    }
}
