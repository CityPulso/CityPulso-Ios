import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 附近活动（对应 Android `SearchScreen`）：系统搜索框 + 位置 + 筛选按钮，活动类型标签，每个标签一页可左右滑的活动卡片。
 */
struct ActivitySearchView: View {
    @State private var model = ActivitySearchModel()
    @State private var search = ""
    @State private var filtersOpen = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        TabView(selection: Binding(get: { model.page }, set: { model.selectPage($0) })) {
            ForEach(ActivitySearchModel.tabs.indices, id: \.self) { index in
                page(index).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) { tabs }
        .navigationTitle("shell_dest_search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: Text("shell_calendar_search_hint"))
        .onChange(of: search) { _, value in model.onSearchChange(value) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: NearRoute.locationPick) {
                    Label {
                        Text(verbatim: model.searches[model.page].location?.label ?? "")
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { filtersOpen = true } label: {
                    Label("nearby_filter_title", systemImage: "line.3.horizontal.decrease")
                }
                .badge(model.filters.activeCount)
            }
        }
        .sheet(isPresented: $filtersOpen) {
            ActivityFilterSheet(activityType: model.activityType, filters: model.filters) { activityType, filters in
                model.store(filters)
                if let index = ActivitySearchModel.tabs.firstIndex(of: activityType) {
                    withAnimation { model.selectPage(index) }
                }
            }
        }
        .task { await model.observe() }
    }

    /** 活动类型标签：横向滚动的胶囊，当前页高亮并跟着翻页滚到可见。 */
    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ActivitySearchModel.tabs.indices, id: \.self) { index in
                        let activityType = ActivitySearchModel.tabs[index]
                        let selected = index == model.page
                        Button {
                            withAnimation { model.selectPage(index) }
                        } label: {
                            HStack(spacing: 4) {
                                if let activityType { Image(activityType.iconAsset).resizable().frame(width: 18, height: 18) }
                                if let activityType { Text(activityType.labelKey) } else { Text("nearby_filter_all_activity_types") }
                            }
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .capsule)
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .onChange(of: model.page) { _, page in withAnimation { proxy.scrollTo(page, anchor: .center) } }
        }
        .background(.bar)
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        let activityType = ActivitySearchModel.tabs[index]
        let search = model.searches[index]
        if !ActivitySearchModel.activitiesAvailable(activityType), let activityType {
            PulsoComingSoonView(title: activityType.labelKey, systemImage: "hourglass")
        } else if let items = search.results.data, !items.isEmpty {
            List {
                ForEach(items, id: \.id) { pin in
                    NavigationLink(value: NearRoute.activity(activityType: NearActivityKind.fromActivityType(pin.activityType), activityId: pin.id)) {
                        NearbyActivityCard(pin: pin, imageURL: model.imageURL(pin.imageId), origin: search.location?.point)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("search_show_on_map_cd", systemImage: "map") {
                            if model.focusOnMap(pin) { shell?.open(.explore) }
                        }
                        .tint(.accentColor)
                    }
                    .onAppear {
                        if pin.id == items.last?.id { search.loadNextPage() }
                    }
                }
                if search.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh(index) }
        } else if search.results.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = search.results.error {
            PulsoLoadErrorView(error) { Task { await model.refresh(index) } }
        } else {
            ContentUnavailableView {
                Label("shell_calendar_nearby_empty", systemImage: "calendar.badge.plus")
            } description: {
                Text("shell_calendar_nearby_empty_hint")
            } actions: {
                if model.isPulser {
                    Button("shell_empty_action_create") { shell?.open(.create) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
