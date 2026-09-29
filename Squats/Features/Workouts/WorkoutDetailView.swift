import SwiftUI

/// Any single workout (planned, in progress, done, skipped). Pushed via `Route.workout`.
/// PLACEHOLDER: owned by the Home & Programs workstream.
struct WorkoutDetailView: View {
    let workoutID: UUID

    @Environment(WorkoutStore.self) private var store

    var body: some View {
        List {
            if let workout = store.workout(workoutID) {
                WorkoutRow(workout: workout)
            }
        }
        .navigationTitle("Workout")
    }
}
