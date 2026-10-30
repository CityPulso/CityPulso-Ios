import SwiftUI

/** 活动与订场（对应 Android `CalendarScreen`）：活动中心整页，标签吸顶，下拉刷新；[initialTab] 为 nil 时停在默认标签。 */
struct CalendarView: View {
    @State private var model: ActivityCenterModel

    init(initialTab: ActivityCenterTab? = nil) {
        _model = State(initialValue: ActivityCenterModel(initialTab: initialTab ?? .hosted))
    }

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
