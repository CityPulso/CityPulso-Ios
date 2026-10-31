import SwiftUI

/** 活动与订场（对应 Android `CalendarScreen`）：活动中心整页，标签吸顶，下拉刷新；[initialTab] 为 nil 时停在默认标签。 */
struct CalendarView: View {
    @State private var model: ActivityCenterModel
    /** 底栏里的根页：没有顶栏，标签直接贴着状态栏（Android 栈底时同样不画顶栏）。 */
    private let isRoot: Bool

    init(initialTab: ActivityCenterTab? = nil, isRoot: Bool = false) {
        self.isRoot = isRoot
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
        .toolbarVisibility(isRoot ? .hidden : .automatic, for: .navigationBar)
        .task { await model.observe() }
    }
}
