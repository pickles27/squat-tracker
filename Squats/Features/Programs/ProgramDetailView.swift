import SwiftUI

/// PLACEHOLDER: owned by the Home & Programs workstream. Pushed via `Route.program`.
struct ProgramDetailView: View {
    let programID: UUID

    @Environment(WorkoutStore.self) private var store

    var body: some View {
        List(store.plannedWorkouts(programID: programID).prefix(10)) { workout in
            NavigationLink(value: Route.workout(workout.id)) { WorkoutRow(workout: workout, showsProgram: false) }
        }
        .navigationTitle(store.program(programID)?.name ?? "Program")
    }
}
