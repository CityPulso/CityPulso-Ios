import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 球馆详情（Android `VenueDetailScreen`）：封面照片、名字和快捷操作（导航、电话、网站、收藏、分享），下面按分段显示
 * 概览 / 场地 / 会员 / 商品与服务 / 赛事 / 课程 / 教练 / 活动 / 订场须知（没有内容的分段不显示）；底部「订某运动的场地」。
 * [sheet] 从深链进来时直接打开会员或时长包面板。
 */
struct VenueDetailView: View {
    let sheet: VenueDetailSheet?
    @State private var model: VenueDetailModel
    @State private var bundles: VenueBundleModel
    @State private var programs: VenueProgramsModel
    @State private var photoPage = 0
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, sheet: VenueDetailSheet? = nil) {
        self.sheet = sheet
        _model = State(initialValue: VenueDetailModel(venueId: venueId))
        _bundles = State(initialValue: VenueBundleModel(venueId: venueId))
        _programs = State(initialValue: VenueProgramsModel(venueId: venueId))
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let venue = model.venue.data {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText(venue)) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(Text("venue_detail_action_share"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.venue.data != nil, let sport = model.sport, let route = model.bookRoute {
                    Button { shell?.push(route) } label: {
                        Text(verbatim: localizedFormat("venue_detail_book_sport_cta", String(localized: sport.loopSport.labelResource))).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: Binding(get: { model.purchase.open }, set: { if !$0 { model.closeMembershipSheet() } })) {
                if let venue = model.venue.data { MembershipPurchaseSheet(model: model, timezone: venue.timezone) }
            }
            .sheet(isPresented: Binding(get: { bundles.purchase.open }, set: { if !$0 { bundles.closeSheet() } })) {
                BundlePurchaseSheet(model: bundles)
            }
            .task { await model.observe() }
            .task { await bundles.observe() }
            .task { await programs.observe() }
            .onChange(of: model.offers.data != nil && !model.myMembership.isLoading) { _, ready in
                if sheet == .membership, ready { model.openMembershipSheetOnce() }
            }
            .onChange(of: bundles.venue != nil && bundles.offers.data != nil) { _, ready in
                if sheet == .bundle, ready { bundles.openSheetOnce() }
            }
            .onAppear {
                // 深链进会员 / 时长包面板时落在列出它们的分段。
                if sheet != nil { model.tab = .membership }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let venue = model.venue.data {
            List {
                hero(venue)
                if venue.status != .published {
                    Section { Text("venue_detail_unpublished").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    tabBar(venue)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                tabContent(venue)
            }
            .listSectionSpacing(.compact)
            .refreshable { model.refresh() }
        } else if let error = model.venue.error {
            if error.kind == .notFound {
                ContentUnavailableView {
                    Label("venue_detail_not_found", systemImage: "building.2")
                } description: {
                    Text("venue_detail_not_found_body")
                } actions: {
                    Button("venue_detail_back_to_explore") { shell?.open(.explore) }
                }
            } else {
                PulsoLoadErrorView(error) { model.refresh() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /* ------------------------------ 头部 ------------------------------ */

    private func hero(_ venue: VenueDetail) -> some View {
        let urls = venue.images.sorted { $0.sortOrder < $1.sortOrder }.compactMap { model.imageURL($0.imageId) }
        return Section {
            ZStack(alignment: .bottomTrailing) {
                if urls.isEmpty {
                    SportCover(url: nil, sport: venue.publishedSports.first?.loopSport ?? .badminton, iconSize: 64)
                } else {
                    TabView(selection: $photoPage) {
                        ForEach(urls.indices, id: \.self) { PulsoRemoteImage(url: urls[$0]).tag($0) }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if urls.count > 1 {
                        Text(verbatim: localizedFormat("venue_detail_photo_counter", photoPage + 1, urls.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: .capsule)
                            .padding(10)
                    }
                }
            }
            .frame(height: 240)
            .clipped()
            .listRowInsets(EdgeInsets())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: venue.displayName).font(.title2.bold())
                    if venue.status != .published {
                        VenueChip(text: String(localized: venue.status.labelResource), tone: RadixScale.amber.lightStep(9))
                    }
                }
                if !venue.building.address.isEmpty {
                    Label { Text(verbatim: venue.building.address) } icon: { Image(systemName: "mappin.and.ellipse") }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if let price = venue.sportEntries.filter({ $0.status == .published }).lowestHourlyPrice {
                        Text(verbatim: localizedFormat("venue_detail_from_price", formatMoney(price, currency: venue.currency, locale: locale)))
                    }
                    Label { Text(verbatim: localizedFormat("shell_views_count", venue.view)) } icon: { Image(systemName: "eye") }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                quickActions(venue)
            }
        }
    }

    /** 导航（菜单：地图里看 / Google 地图 / 其他地图）、电话、网站、收藏。 */
    private func quickActions(_ venue: VenueDetail) -> some View {
        HStack(spacing: 10) {
            if let lat = venue.building.locationLat, let lng = venue.building.locationLng {
                Menu {
                    Button { openOnExplore() } label: { Label("venue_detail_maps_in_app", systemImage: "map") }
                    if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)") {
                        Button { openURL(url) } label: { Label("venue_detail_maps_google", systemImage: "arrow.up.right.square") }
                    }
                    if let url = URL(string: "maps://?daddr=\(lat),\(lng)") {
                        Button { openURL(url) } label: { Label("venue_detail_maps_other", systemImage: "arrow.up.right.square") }
                    }
                } label: {
                    quickAction("arrow.triangle.turn.up.right.diamond", "venue_detail_action_directions")
                }
            }
            if let phone = venue.phone, !phone.isEmpty, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                Button { openURL(url) } label: { quickAction("phone", "venue_detail_action_call") }
            }
            if let site = venue.website, !site.isEmpty, let url = URL(string: site.hasPrefix("http") ? site : "https://\(site)") {
                Button { openURL(url) } label: { quickAction("globe", "venue_detail_website") }
            }
            FavoriteHeart(target: .venue, id: venue.id, name: venue.displayName)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func quickAction(_ systemImage: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.body.weight(.semibold)).frame(width: 44, height: 44).background(Color(.tertiarySystemFill), in: .circle)
            Text(label).font(.caption2)
        }
        .foregroundStyle(Color.primary)
    }

    private func openOnExplore() {
        if model.focusOnExplore() { shell?.open(.explore) }
    }

    private func shareText(_ venue: VenueDetail) -> String {
        [venue.displayName, venue.building.address].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /* ------------------------------ 分段 ------------------------------ */

    /** 没内容的分段不放进来（WEB `shown`）。 */
    private func visibleTabs(_ venue: VenueDetail) -> [VenueInfoTab] {
        VenueInfoTab.allCases.filter { tab in
            switch tab {
            case .overview, .sessions: true
            case .courts: !venue.sportEntries.isEmpty
            case .membership: !model.shownOffers.isEmpty || !bundles.shownOffers.isEmpty
            case .offerings: !model.activeOfferings.isEmpty
            case .tournaments: !programs.tournaments.items.isEmpty
            case .courses: !programs.courses.isEmpty
            case .coaches: !programs.coaches.isEmpty || programs.isCoach
            case .policies: !venue.sportEntries.isEmpty || !(venue.bookingInstructions ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    private func tabBar(_ venue: VenueDetail) -> some View {
        let tabs = visibleTabs(venue)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { tab in
                    let isOn = tab == currentTab(venue)
                    Button { model.tab = tab } label: {
                        Text(tab.labelKey)
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func currentTab(_ venue: VenueDetail) -> VenueInfoTab {
        visibleTabs(venue).contains(model.tab) ? model.tab : .overview
    }

    @ViewBuilder
    private func tabContent(_ venue: VenueDetail) -> some View {
        switch currentTab(venue) {
        case .overview: VenueOverviewSections(venue: venue, distanceM: model.distanceM, map: model.map, onOpenOnMap: { openOnExplore() })
        case .courts: VenueSportsSection(model: model)
        case .membership:
            VenueMembershipSection(model: model) { shell?.push(LoopRoute.myMembership(membershipId: $0.id)) }
            VenueBundleSection(model: bundles) { shell?.push(LoopRoute.wallet(tab: .bundles)) }
        case .offerings: VenueOfferingsSection(offerings: model.activeOfferings, imageURL: { model.imageURL($0) })
        case .tournaments: VenueTournamentsSection(programs: programs, imageURL: { model.imageURL($0) })
        case .courses: VenueCoursesSection(programs: programs, imageURL: { model.imageURL($0) })
        case .coaches: VenueCoachesSection(programs: programs, imageURL: { model.imageURL($0) })
        case .sessions: BuildingEventsSection(events: model.buildingEvents, imageURL: { model.imageURL($0) }, onRetry: { model.refresh() })
        case .policies: VenuePoliciesSection(model: model, venue: venue)
        }
    }
}

extension VenueInfoTab {
    var labelKey: LocalizedStringKey {
        switch self {
        case .overview: "venue_detail_tab_overview"
        case .courts: "venue_detail_tab_courts"
        case .membership: "venue_detail_tab_membership"
        case .offerings: "venue_detail_tab_offerings"
        case .tournaments: "venue_detail_tab_tournaments"
        case .courses: "venue_detail_tab_courses"
        case .coaches: "venue_detail_tab_coaches"
        case .sessions: "venue_detail_tab_events"
        case .policies: "venue_detail_tab_policies"
        }
    }
}

extension PublicationStatus {
    var labelResource: String.LocalizationValue {
        switch self {
        case .draft: "venue_venue_status_draft"
        case .published: "venue_venue_status_published"
        case .suspended: "venue_venue_status_suspended"
        }
    }
}
