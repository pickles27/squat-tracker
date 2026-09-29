import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    /// Grouped background behind cards; adapts to light/dark mode.
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    /// Card surface on top of `appBackground`.
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

/// Colors that tell programs apart in lists and the calendar.
enum ProgramPalette {
    static let colors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .indigo, .red]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    static func color(for program: Program?) -> Color {
        color(program?.colorIndex ?? 0)
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    /// Rounded card on the grouped background.
    func card() -> some View {
        modifier(CardModifier())
    }
}

extension DisplayStatus {
    var label: String {
        switch self {
        case .upcoming: "Planned"
        case .today: "Today"
        case .overdue: "Overdue"
        case .missed: "Missed"
        case .inProgress: "In progress"
        case .completed: "Done"
        case .skipped: "Skipped"
        }
    }

    var color: Color {
        switch self {
        case .upcoming: .secondary
        case .today: .accentColor
        case .overdue: .orange
        case .missed: .red
        case .inProgress: .blue
        case .completed: .green
        case .skipped: .gray
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming: "calendar"
        case .today: "sun.max.fill"
        case .overdue: "exclamationmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .inProgress: "timer"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.fill"
        }
    }
}
