import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 附近活动（对应 Android `SearchScreen`）：系统搜索框 + 位置 + 筛选按钮，运动标签，每个标签一页可左右滑的活动卡片。
 */
struct EventSearchView: View {
    @State private var model = EventSearchModel()
    @State private var search = ""
    @State private var filtersOpen = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: Binding(get: { model.page }, set: { model.selectPage($0) })) {
                ForEach(EventSearchModel.tabs.indices, id: \.self) { index in
                    page(index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("shell_dest_search")
        // 底栏根页：没有顶栏（Android 同样只有状态栏底色 + 自己的搜索行）。
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onChange(of: search) { _, value in model.onSearchChange(value) }
        .sheet(isPresented: $filtersOpen) {
            EventFilterSheet(sport: model.sport, filters: model.filters) { sport, filters in
                model.store(filters)
                if let index = EventSearchModel.tabs.firstIndex(of: sport) {
                    withAnimation { model.selectPage(index) }
                }
            }
        }
        .task { await model.observe() }
    }

    /** 位置 / 搜索双槽 + 筛选方钮，下面运动标签（全部 + 各运动），跟着翻页。 */
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: PulsoSpace.s2) {
                PulsoAddressSearchBar(
                    locationLabel: model.searches[model.page].location?.label,
                    unknownLocation: Text("shell_calendar_location_unknown"),
                    search: $search,
                    searchHint: Text("shell_calendar_search_hint")
                ) { shell?.push(LoopRoute.locationPick) }
                Button { filtersOpen = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(palette.gray.step(12))
                        .frame(width: PulsoControlSize.compact.height, height: PulsoControlSize.compact.height)
                        .background(palette.gray.step(3), in: palette.controlShape)
                        .overlay(alignment: .topTrailing) {
                            if model.filters.activeCount > 0 {
                                Text(verbatim: "\(model.filters.activeCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, PulsoSpace.s1)
                                    .background(palette.error, in: Capsule())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.pulsoPressBounce)
                .accessibilityLabel(Text("nearby_filter_title"))
            }
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
            PulsoUnderlineTabRow(
                Array(EventSearchModel.tabs.indices),
                selection: Binding(get: { model.page }, set: { page in withAnimation { model.selectPage(page) } }),
                image: { EventSearchModel.tabs[$0].map { Image($0.iconAsset) } }
            ) { index in
                if let sport = EventSearchModel.tabs[index] { Text(sport.labelKey) } else { Text("nearby_filter_all_sports") }
            }
        }
        .background(palette.background)
    }

    @ViewBuilder
    private func page(_ index: Int) -> some View {
        let sport = EventSearchModel.tabs[index]
        let search = model.searches[index]
        if !EventSearchModel.eventsAvailable(sport), let sport {
            PulsoEmptyState(Text(sport.labelKey), description: Text("coming_soon_subtitle"), style: .comingSoon)
        } else if let items = search.results.data, !items.isEmpty {
            ScrollView {
                LazyVStack(spacing: PulsoSpace.s2) {
                    ForEach(items, id: \.id) { pin in
                        NavigationLink(value: LoopRoute.event(sport: LoopSport.fromEventType(pin.eventType), eventId: pin.id)) {
                            PulsoCard {
                                NearbyEventCard(pin: pin, imageURL: model.imageURL(pin.imageId), origin: search.location?.point)
                                    .padding(PulsoSpace.s3)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("search_show_on_map_cd", systemImage: "map") {
                                if model.focusOnMap(pin) { shell?.open(.explore) }
                            }
                        }
                        .onAppear {
                            if pin.id == items.last?.id { search.loadNextPage() }
                        }
                    }
                    if search.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, PulsoSpace.s4)
                .padding(.vertical, PulsoSpace.s2)
            }
            .refreshable { await model.refresh(index) }
        } else if search.results.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = search.results.error {
            PulsoLoadErrorView(error) { Task { await model.refresh(index) } }
        } else {
            PulsoEmptyState(Text("shell_calendar_nearby_empty"), description: Text("shell_calendar_nearby_empty_hint"), style: .calendar) {
                if model.isPulser {
                    Button("shell_empty_action_create") { shell?.open(.create) }
                        .buttonStyle(.pulso())
                }
            }
        }
    }
}
