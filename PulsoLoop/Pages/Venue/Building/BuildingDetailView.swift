import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一栋场馆建筑（Android `BuildingDetailViewModel`）：建筑本身、里面的球馆（有的话）、在这里办的活动。 */
@MainActor
@Observable
final class BuildingDetailModel {
    let buildingId: String

    private(set) var building = Loadable<BuildingItem>()
    /** 这栋楼里营业的球馆；没有（或读不到）时 nil。 */
    private(set) var venue: VenueDetail?
    var tab = VenueDetailTab.venue
    let events = BuildingEvents()

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
            events.load(buildingId: building.data?.id ?? "", session: session)
        }
        events.cancel()
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
                    self.events.load(buildingId: buildingId, session: self.sessionStore.state.value)
                } catch {
                    self.building = Loadable(data: self.building.data, isLoading: false, error: UiError(error))
                }
            },
            {
                // 球馆卡是附加的：读不到就停在「还没有球馆」，不让整页失败。
                if let venue = try? await venueService.getVenueByBuilding(buildingId) { self.venue = venue }
            },
        ])
    }
}

/** 场馆建筑（Android `BuildingDetailScreen`）：照片、名字和地址、收藏；「球馆 / 活动」两个分段。 */
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
                let photos = building.images.sorted { $0.sortOrder < $1.sortOrder }.compactMap { model.imageURL($0.imageId) }
                if !photos.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photos.indices, id: \.self) { index in
                                    PulsoRemoteImage(url: photos[index])
                                        .frame(width: 260, height: 170)
                                        .clipShape(palette.cardShape)
                                        .accessibilityLabel(Text(verbatim: localizedFormat("building_detail_photo", building.name)))
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    // 名字、类型和地址直接在页面上；收藏在顶栏（Android 场馆建筑页）。
                    VStack(alignment: .leading, spacing: PulsoSpace.s2) {
                        Text(verbatim: building.name).font(.title.bold()).foregroundStyle(palette.text)
                        Text(BuildingType.fromWire(building.buildingType).labelKey).font(.subheadline).foregroundStyle(palette.secondaryText)
                        if !building.address.isEmpty {
                            Label { Text(verbatim: building.address) } icon: { Image(systemName: "mappin.and.ellipse") }
                                .font(.subheadline)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: PulsoSpace.s2, leading: 0, bottom: PulsoSpace.s3, trailing: 0))
                    PulsoUnderlineTabRow([VenueDetailTab.venue, .events], selection: $model.tab) { tab in
                        Text(tab == .venue ? "venue_detail_tab_venue" : "venue_detail_tab_events")
                    }
                    .listRowInsets(EdgeInsets())
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                switch model.tab {
                case .venue:
                    Section {
                        if let venue = model.venue {
                            NavigationLink(value: LoopRoute.venue(venueId: venue.id)) {
                                HStack(spacing: 12) {
                                    SportCover(url: model.imageURL(venue.images.min { $0.sortOrder < $1.sortOrder }?.imageId), sport: venue.publishedSports.first?.loopSport ?? .badminton, iconSize: 24)
                                        .frame(width: 64, height: 64)
                                        .clipShape(.rect(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: venue.displayName).font(.headline)
                                        PulsoFlowLayout(spacing: 4) {
                                            ForEach(venue.publishedSports, id: \.self) { SportTag(sport: $0.loopSport) }
                                        }
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("building_detail_no_venue").font(.subheadline.weight(.semibold))
                                Text("building_detail_no_venue_body").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                case .events:
                    BuildingEventsSection(events: model.events, imageURL: { model.imageURL($0) }, onRetry: { Task { await model.refresh() } })
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle(Text(verbatim: building.name))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteHeart(target: .building, id: building.id, name: building.name)
                }
            }
        } else if model.building.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.building.error, error.kind != .notFound {
            PulsoLoadErrorView(error) { Task { await model.refresh() } }
        } else {
            ContentUnavailableView {
                Label("building_detail_not_found", systemImage: "building")
            } description: {
                Text("building_detail_not_found_body")
            } actions: {
                Button("venue_detail_back_to_explore") { shell?.open(.explore) }
            }
        }
    }
}
