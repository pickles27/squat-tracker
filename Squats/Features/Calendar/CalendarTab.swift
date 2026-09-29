import SwiftUI

/// Calendar tab. PLACEHOLDER: owned by the Calendar & Settings workstream.
struct CalendarTab: View {
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    var body: some View {
        NavigationStack {
            ScrollView {
                MonthCalendarView(programID: nil, selectedDay: $selectedDay)
                    .padding()
            }
            .navigationTitle("Calendar")
            .appNavigationDestinations()
        }
    }
}
