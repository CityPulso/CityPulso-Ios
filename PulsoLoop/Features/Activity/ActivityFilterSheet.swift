import SwiftUI

/** 活动中心的筛选（对应 Android `ActivityFilterPanel`）：「我参加的」分组、先后顺序、看已结束。 */
struct ActivityFilterSheet: View {
    let tab: ActivityCenterTab
    let filter: ActivityFilter
    let onApply: (ActivityFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ActivityFilter()

    var body: some View {
        NavigationStack {
            Form {
                if tab == .joined {
                    Picker("activity_filter_group", selection: $draft.joined) {
                        ForEach(JoinedFilter.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    }
                }
                Picker("activity_filter_sort", selection: $draft.sortAsc) {
                    Text("shell_home_sort_earliest").tag(true)
                    Text("shell_home_sort_latest").tag(false)
                }
                if tab == .courtBookings {
                    Picker("activity_tab_bookings", selection: $draft.bookings) {
                        Text("court_bookings_tabs_upcoming").tag(CourtBookingListTab.upcoming)
                        Text("court_bookings_tabs_past").tag(CourtBookingListTab.past)
                    }
                } else {
                    Toggle("activity_filter_show_ended", isOn: $draft.showEnded)
                }
            }
            .navigationTitle("activity_filter_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("nearby_filter_reset") { draft = ActivityFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("nearby_filter_apply", role: .confirm) {
                        onApply(draft)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = filter }
        .presentationDetents([.medium])
    }
}
