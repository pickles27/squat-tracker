import SwiftUI

/// Program setup sheet. PLACEHOLDER: owned by the Home & Programs workstream.
struct NewProgramView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("New program")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
        }
    }
}
