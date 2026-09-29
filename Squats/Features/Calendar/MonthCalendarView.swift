import SwiftUI

/// Month grid with workout markers; tapping a day selects it. Pass a program ID to show only that
/// program. PLACEHOLDER: owned by the Calendar & Settings workstream; also used by ProgramDetailView.
struct MonthCalendarView: View {
    let programID: UUID?
    @Binding var selectedDay: Date

    var body: some View {
        DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
            .datePickerStyle(.graphical)
    }
}
