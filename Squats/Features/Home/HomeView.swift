import SwiftUI

/// Home tab. PLACEHOLDER: owned by the Home & Programs workstream.
struct HomeView: View {
    @Environment(WorkoutStore.self) private var store
    @State private var showingNewProgram = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.activePrograms) { program in
                    NavigationLink(program.name, value: Route.program(program.id))
                }
            }
            .navigationTitle("Home")
            .toolbar {
                Button("New program", systemImage: "plus") { showingNewProgram = true }
            }
            .sheet(isPresented: $showingNewProgram) { NewProgramView() }
            .appNavigationDestinations()
        }
    }
}
