import SwiftUI

/// Move a planned workout to another date, optionally shifting all following workouts by the same amount.
/// PLACEHOLDER: owned by the Home & Programs workstream.
struct RescheduleSheet: View {
    let workoutID: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Reschedule")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
        }
    }
}
