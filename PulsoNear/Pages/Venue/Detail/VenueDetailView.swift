import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 门店详情（Android `VenueDetailScreen`）：封面照片、名字和快捷操作（导航、电话、网站、收藏、分享），下面按分段显示
 * 概览 / 桌台 / 会员 / 商品与服务 / 活动 / 预约须知（没有内容的分段不显示）；底部「预约某活动类型」。
 * [sheet] 从深链进来时直接打开会员面板。
 */
struct VenueDetailView: View {
    let sheet: VenueDetailSheet?
    @State private var model: VenueDetailModel
    @State private var photoPage = 0
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulsoPalette) private var palette
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, sheet: VenueDetailSheet? = nil) {
        self.sheet = sheet
        _model = State(initialValue: VenueDetailModel(venueId: venueId))
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if model.venue.data != nil, let activityType = model.activityType, let route = model.bookRoute {
                    Button { shell?.push(route) } label: {
                        Text(verbatim: localizedFormat("venue_detail_book_activity_type_cta", String(localized: activityType.kind.labelResource))).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pulso(fullWidth: true))
                    .padding(PulsoSpace.s4)
                    .background(palette.background)
                }
            }
            .sheet(isPresented: Binding(get: { model.purchase.open }, set: { if !$0 { model.closeMembershipSheet() } })) {
                if let venue = model.venue.data { MembershipPurchaseSheet(model: model, timezone: venue.timezone) }
            }
            .task { await model.observe() }
            .onChange(of: model.offers.data != nil && !model.myMembership.isLoading) { _, ready in
                if sheet == .membership, ready { model.openMembershipSheetOnce() }
            }
            .onAppear {
                // 深链进会员面板时落在列出它的分段。
                if sheet == .membership { model.tab = .membership }
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
            .ignoresSafeArea(edges: .top)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { model.refresh() }
        } else if let error = model.venue.error {
            if error.kind == .notFound {
                PulsoEmptyState(Text("venue_detail_not_found"), description: Text("venue_detail_not_found_body")) {
                    Button("venue_detail_back_to_explore") { shell?.open(.explore) }.buttonStyle(.pulso())
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
                    ActivityTypeCover(url: nil, activityType: venue.publishedActivityTypes.first?.kind ?? .boardGame, iconSize: 64)
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
            .frame(height: 300)
            .containerRelativeFrame(.horizontal)
            .clipped()
            .overlay(alignment: .top) { heroButtons(venue) }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            if urls.count > 1 {
                thumbnails(urls)
                    .listRowInsets(EdgeInsets(top: PulsoSpace.s3, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: venue.displayName).font(.title2.bold()).foregroundStyle(palette.text)
                    if venue.status != .published {
                        VenueChip(text: String(localized: venue.status.labelResource), tone: RadixScale.amber.lightStep(9))
                    }
                }
                if !venue.building.address.isEmpty {
                    Text(verbatim: venue.building.address).font(.subheadline).foregroundStyle(palette.secondaryText)
                }
                HStack(spacing: 12) {
                    if let price = venue.lowestHourlyPrice {
                        Text(verbatim: localizedFormat("venue_detail_from_price", formatMoney(price, currency: venue.currency, locale: locale)))
                    }
                    Label { Text(verbatim: localizedFormat("shell_views_count", venue.view)) } icon: { Image(systemName: "eye") }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette.secondaryText)
                if let status = venueOpenStatus(venueWeek(venue.hours), timezone: venue.timezone) {
                    VenueOpenChip(status: status)
                }
                quickActions(venue)
            }
            .listRowInsets(EdgeInsets(top: PulsoSpace.s3, leading: 0, bottom: PulsoSpace.s3, trailing: 0))
            .listRowBackground(Color.clear)
        }
        .listRowSeparator(.hidden)
    }

    /** 封面上的返回、分享、收藏（Android 详情页顶栏叠在照片上）。 */
    private func heroButtons(_ venue: VenueDetail) -> some View {
        HStack(spacing: PulsoSpace.s2) {
            PulsoIconButton("arrow.left", label: Text("profile_back")) { dismiss() }
            Spacer()
            ShareLink(item: shareText(venue)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: PulsoControlSize.small.height, height: PulsoControlSize.small.height)
                    .background(.black.opacity(0.36), in: palette.controlShape)
            }
            FavoriteHeart(target: .venue, id: venue.id, name: venue.displayName, style: .overlay)
        }
        .padding(.horizontal, PulsoSpace.s4)
        .safeAreaPadding(.top)
    }

    /** 照片缩略图一排，当前那张描强调色边。 */
    private func thumbnails(_ urls: [URL]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PulsoSpace.s2) {
                ForEach(urls.indices, id: \.self) { index in
                    Button { withAnimation { photoPage = index } } label: {
                        PulsoRemoteImage(url: urls[index])
                            .frame(width: 80, height: 56)
                            .clipShape(palette.innerShape)
                            .overlay {
                                if index == photoPage { palette.innerShape.strokeBorder(palette.accent.step(9), lineWidth: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /** 导航（菜单：地图里看 / Google 地图 / 其他地图）、电话、网站、收藏。 */
    private func quickActions(_ venue: VenueDetail) -> some View {
        HStack(spacing: PulsoSpace.s2) {
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
            ShareLink(item: shareText(venue)) { quickAction("square.and.arrow.up", "venue_detail_action_share") }
            if let site = venue.website, !site.isEmpty, let url = URL(string: site.hasPrefix("http") ? site : "https://\(site)") {
                Button { openURL(url) } label: { quickAction("globe", "venue_detail_website") }
            }
            FavoriteHeart(target: .venue, id: venue.id, name: venue.displayName, style: .tile)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.top, PulsoSpace.s2)
    }

    /** 快捷操作（Android 详情页的一排）：强调色 step3 方块里 step9 图标，下面小字。 */
    private func quickAction(_ systemImage: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: PulsoSpace.s1) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.accent.step(9))
                .frame(width: 48, height: 48)
                .background(palette.accent.step(3), in: palette.innerShape)
            Text(label).font(.caption2).foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
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
            case .overview, .activities: true
            case .spaces: !venue.activityTypeEntries.isEmpty
            case .membership: !model.shownOffers.isEmpty
            case .offerings: !model.activeOfferings.isEmpty
            case .policies: !venue.activityTypeEntries.isEmpty || !(venue.bookingInstructions ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    /** 一级分段（Android `PulsoUnderlineTabRow`）：没内容的分段不放进来。 */
    private func tabBar(_ venue: VenueDetail) -> some View {
        PulsoUnderlineTabRow(visibleTabs(venue), selection: Binding(get: { currentTab(venue) }, set: { model.tab = $0 })) { Text($0.labelKey) }
    }

    private func currentTab(_ venue: VenueDetail) -> VenueInfoTab {
        visibleTabs(venue).contains(model.tab) ? model.tab : .overview
    }

    @ViewBuilder
    private func tabContent(_ venue: VenueDetail) -> some View {
        switch currentTab(venue) {
        case .overview: VenueOverviewSections(venue: venue, distanceM: model.distanceM, map: model.map, onOpenOnMap: { openOnExplore() })
        case .spaces: VenueActivityTypesSection(model: model)
        case .membership:
            VenueMembershipSection(model: model) { shell?.push(NearRoute.myMembership(membershipId: $0.id)) }
        case .offerings: VenueOfferingsSection(offerings: model.activeOfferings, imageURL: { model.imageURL($0) })
        case .activities: BuildingActivitiesSection(activities: model.buildingActivities, imageURL: { model.imageURL($0) }, onRetry: { model.refresh() })
        case .policies: VenuePoliciesSection(model: model, venue: venue)
        }
    }
}

extension VenueInfoTab {
    var labelKey: LocalizedStringKey {
        switch self {
        case .overview: "venue_detail_tab_overview"
        case .spaces: "venue_detail_tab_spaces"
        case .membership: "venue_detail_tab_membership"
        case .offerings: "venue_detail_tab_offerings"
        case .activities: "venue_detail_tab_activities"
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
