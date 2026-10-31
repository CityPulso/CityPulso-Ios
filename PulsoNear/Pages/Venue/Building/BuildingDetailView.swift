import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一栋场馆建筑（Android `BuildingDetailViewModel`）：建筑本身、里面的门店（有的话）、在这里办的活动。 */
@MainActor
@Observable
final class BuildingDetailModel {
    let buildingId: String

    private(set) var building = Loadable<BuildingItem>()
    /** 这栋楼里营业的门店；没有（或读不到）时 nil。 */
    private(set) var venue: VenueDetail?
    var tab = VenueDetailTab.venue
    let activities = BuildingActivities()

    @ObservationIgnored @Injected(\.buildingService) private var buildingService
    @ObservationIgnored @Injected(\.venueService) private var venueService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(buildingId: String) {
        self.buildingId = buildingId
    }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        await refresh()
        for await session in sessionStore.state.values() {
            activities.load(buildingId: building.data?.id ?? "", session: session)
        }
        activities.cancel()
    }

    func refresh() async {
        building = Loadable(data: building.data, isLoading: true)
        let buildingService = buildingService
        let venueService = venueService
        let buildingId = buildingId
        await concurrently([
            {
                do {
                    self.building = Loadable(data: try await buildingService.getBuilding(id: buildingId), isLoading: false)
                    self.activities.load(buildingId: buildingId, session: self.sessionStore.state.value)
                } catch {
                    self.building = Loadable(data: self.building.data, isLoading: false, error: UiError(error))
                }
            },
            {
                // 门店卡是附加的：读不到就停在「还没有门店」，不让整页失败。
                if let venue = try? await venueService.getVenueByBuilding(buildingId) { self.venue = venue }
            },
        ])
    }
}

/** 场馆建筑（Android `BuildingDetailScreen`）：照片、名字和地址、收藏；「门店 / 活动」两个分段。 */
struct BuildingDetailView: View {
    @Environment(\.pulsoPalette) private var palette
    @State private var model: BuildingDetailModel
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(buildingId: String) {
        _model = State(initialValue: BuildingDetailModel(buildingId: buildingId))
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        if let building = model.building.data {
            List {
                Section {
                    let photos = building.images.sorted { $0.sortOrder < $1.sortOrder }.compactMap { model.imageURL($0.imageId) }
                    if !photos.isEmpty {
                        // 第一张宽，后面的窄，横着滑；最后一张后面留一点空（Android `BuildingPhotoRow`）。
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PulsoSpace.s2) {
                                ForEach(photos.indices, id: \.self) { index in
                                    PulsoRemoteImage(url: photos[index])
                                        .frame(width: index == 0 ? 240 : 120, height: 160)
                                        .clipShape(palette.innerShape)
                                        .accessibilityLabel(Text(verbatim: localizedFormat("building_detail_photo", building.name)))
                                }
                            }
                            .padding(.horizontal, PulsoSpace.s4)
                            .padding(.trailing, PulsoSpace.s8)
                        }
                        .listRowInsets(EdgeInsets(top: PulsoSpace.s4, leading: 0, bottom: PulsoSpace.s2, trailing: 0))
                    }
                    // 名字和地址直接在页面上；收藏在顶栏（Android 场馆建筑页）。
                    VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                        Text(verbatim: building.name).font(.title2.weight(.semibold)).foregroundStyle(palette.text)
                        if !building.address.isEmpty {
                            HStack(alignment: .top, spacing: PulsoSpace.s2) {
                                Image(systemName: "mappin")
                                Text(verbatim: building.address)
                            }
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: PulsoSpace.s2, leading: PulsoSpace.s4, bottom: PulsoSpace.s2, trailing: PulsoSpace.s4))
                    PulsoUnderlineTabRow([VenueDetailTab.venue, .activities], selection: $model.tab) { tab in
                        Text(tab == .venue ? "venue_detail_tab_venue" : "venue_detail_tab_activities")
                    }
                    .listRowInsets(EdgeInsets(top: PulsoSpace.s2, leading: PulsoSpace.s4, bottom: PulsoSpace.s2, trailing: PulsoSpace.s4))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                switch model.tab {
                case .venue:
                    Section {
                        if let venue = model.venue {
                            venueCard(venue)
                        } else {
                            PulsoEmptyState(Text("building_detail_no_venue"), description: Text("building_detail_no_venue_body"))
                                .padding(.top, PulsoSpace.s6)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: PulsoSpace.s2, leading: PulsoSpace.s4, bottom: PulsoSpace.s2, trailing: PulsoSpace.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                case .activities:
                    BuildingActivitiesSection(activities: model.activities, imageURL: { model.imageURL($0) }, onRetry: { Task { await model.refresh() } })
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh() }
            .navigationTitle(Text(verbatim: building.name))
            .toolbar {
                // Android 顶栏的心形是一个图标，不垫底。
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteHeart(target: .building, id: building.id, name: building.name)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else if model.building.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.building.error, error.kind != .notFound {
            PulsoLoadErrorView(error) { Task { await model.refresh() } }
        } else {
            PulsoEmptyState(Text("building_detail_not_found"), description: Text("building_detail_not_found_body")) {
                Button("venue_detail_back_to_explore") { shell?.open(.explore) }.buttonStyle(.pulso())
            }
        }
    }

    /** 楼里营业的那家：封面、项目、现在开没开，点开进详情（Android `BuildingVenueCard`）。 */
    private func venueCard(_ venue: VenueDetail) -> some View {
        let cover = venue.images.min { $0.sortOrder < $1.sortOrder }?.imageId ?? venue.building.images.min { $0.sortOrder < $1.sortOrder }?.imageId
        return Button { shell?.push(NearRoute.venue(venueId: venue.id)) } label: {
            PulsoCard {
                HStack(spacing: PulsoSpace.s3) {
                    ActivityTypeCover(url: model.imageURL(cover), activityType: venue.activityTypes.first?.kind ?? .boardGame, iconSize: 24)
                        .frame(width: 72, height: 72)
                        .clipShape(palette.innerShape)
                    VStack(alignment: .leading, spacing: PulsoSpace.s1) {
                        Text(verbatim: venue.displayName).font(.headline).foregroundStyle(palette.text).lineLimit(2)
                        if !venue.activityTypes.isEmpty {
                            Text(verbatim: venue.activityTypes.map { String(localized: $0.kind.labelResource) }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                        }
                        if let status = venueOpenStatus(venueWeek(venue.hours), timezone: venue.timezone) {
                            VenueOpenChip(status: status)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").foregroundStyle(palette.secondaryText)
                }
                .padding(PulsoSpace.s3)
            }
        }
        .buttonStyle(.plain)
    }
}
