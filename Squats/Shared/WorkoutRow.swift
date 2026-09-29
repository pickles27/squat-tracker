import SwiftUI

/// Compact row for a workout in any list: date, session title, lifts, program and status.
struct WorkoutRow: View {
    let workout: Workout
    var showsProgram = true

    @Environment(WorkoutStore.self) private var store

    var body: some View {
        let program = store.program(workout.programID)
        let header = store.header(for: workout)
        let status = store.displayStatus(of: workout)
        let date = store.displayDate(of: workout)

        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProgramPalette.color(for: program))
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(header?.title ?? "Workout")
                    .font(.headline)
                Text(header?.liftNames.joined(separator: " · ") ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if showsProgram, let program {
                    Text(program.name)
                        .font(.caption)
                        .foregroundStyle(ProgramPalette.color(for: program))
                }
            }

            Spacer(minLength: 8)
            StatusBadge(status: status)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct StatusBadge: View {
    let status: DisplayStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}
