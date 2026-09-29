import Foundation
import Observation

/// Which in-progress workout is focused and whether workout mode is expanded (full screen) or minimized.
/// Several workouts can be in progress at once; only the focused one is shown.
@MainActor
@Observable
final class SessionCoordinator {
    var focusedWorkoutID: UUID?
    var isExpanded = false

    /// Shows workout mode for an in-progress workout (start it with the store first).
    func open(_ workoutID: UUID) {
        focusedWorkoutID = workoutID
        isExpanded = true
    }

    /// Hides workout mode; the workout keeps running and shows in the mini bar.
    func minimize() {
        isExpanded = false
    }

    /// Call after finishing or discarding a workout: closes workout mode and focuses another active one, if any.
    func close(remaining inProgress: [Workout]) {
        isExpanded = false
        focusedWorkoutID = inProgress.last?.id
    }
}
