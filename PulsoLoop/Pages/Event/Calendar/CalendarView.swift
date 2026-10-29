import SwiftUI

/** 日历（对应 Android `CalendarScreen`）：活动中心整页，标签吸顶，下拉刷新。 */
struct CalendarView: View {
    @State private var model = ActivityCenterModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: .sectionHeaders) {
                ActivityCenterSection(model: model)
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle("shell_dest_calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
    }
}
