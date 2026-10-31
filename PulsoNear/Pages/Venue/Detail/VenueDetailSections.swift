import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* 门店详情各分段（Android `VenueDetailOverview` / `VenueDetailSections` 和会员卡片）。 */

/** 概览：简介（展开 / 收起）、各活动类型桌台数、设施，营业时间，位置（距离 + 地图预览 + 在地图上看）。 */
struct VenueOverviewSections: View {
    let venue: VenueDetail
    let distanceM: Double?
    let map: ResolvedMapPreference
    let onOpenOnMap: () -> Void

    @State private var expanded = false
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    var body: some View {
        let about = venue.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !about.isEmpty || !venue.activityTypeEntries.isEmpty || !venue.amenities.isEmpty {
            Section("venue_detail_sections_about") {
                if !about.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: about).font(.body).foregroundStyle(.secondary).lineLimit(expanded ? nil : 4)
                        Button((expanded ? "venue_detail_read_less" : "venue_detail_read_more") as LocalizedStringKey) { expanded.toggle() }
                            .font(.footnote)
                            .buttonStyle(.borderless)
                    }
                }
                if !venue.activityTypeEntries.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(venue.activityTypeEntries, id: \.activityType) { entry in
                            HStack(spacing: 8) {
                                Image(entry.activityType.kind.iconAsset).resizable().scaledToFit().frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(entry.activityType.kind.labelKey).font(.subheadline.weight(.medium))
                                    if entry.spaceCount > 0 {
                                        Text(verbatim: localizedFormat("venue_detail_spaces", entry.spaceCount)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(PulsoSpace.s3)
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1) }
                        }
                    }
                }
                if !venue.amenities.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("venue_detail_sections_amenities").font(.caption).foregroundStyle(.secondary)
                        PulsoFlowLayout(spacing: 6) {
                            ForEach(venue.amenities, id: \.self) { amenity in
                                Label { Text(verbatim: amenity.name) } icon: { Image(systemName: catalogSystemImage(amenity.icon)) }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemFill), in: .capsule)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: PulsoSpace.s2, leading: PulsoSpace.s4, bottom: PulsoSpace.s2, trailing: PulsoSpace.s4))
        }
        hours
        location
    }

    /** 一周营业时间，周一在前；连着几天时间一样的合成一行（WEB `OpeningHoursCard`）。 */
    @ViewBuilder
    private var hours: some View {
        let runs = groupWeekHours(venueWeek(venue.hours))
        if !runs.allSatisfy({ $0.hours == nil }) {
            Section("venue_detail_sections_hours") {
                ForEach(runs, id: \.fromDay) { run in
                    LabeledContent {
                        Text(verbatim: run.hours.map { localizedFormat("venue_detail_hours_clock_range", $0.opensAt, $0.closesAt) } ?? String(localized: "venue_detail_hours_closed"))
                            .monospacedDigit()
                            .foregroundStyle(run.hours == nil ? Color.secondary : Color.primary)
                    } label: {
                        Text(verbatim: run.fromDay == run.toDay ? weekday(run.fromDay) : localizedFormat("venue_detail_hours_day_range", weekday(run.fromDay), weekday(run.toDay)))
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func weekday(_ iso: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortStandaloneWeekdaySymbols[iso % 7]
    }

    @ViewBuilder
    private var location: some View {
        let lat = venue.building.locationLat
        let lng = venue.building.locationLng
        if !venue.building.address.isEmpty || (lat != nil && lng != nil) {
            Section("venue_detail_sections_location") {
                if let distanceM {
                    Text(verbatim: localizedFormat("venue_detail_location_away", distanceLabel(distanceM))).font(.subheadline).foregroundStyle(.secondary)
                }
                if let lat, let lng {
                    NearMapView(map: map, initialCenter: (lat, lng), initialZoom: 15, camera: MapCameraRequest(id: 1, latitude: lat, longitude: lng, zoom: 15))
                        .allowsHitTesting(false)
                        .overlay {
                            Image(systemName: "mappin").font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.accentColor).offset(y: -15)
                        }
                        .aspectRatio(2, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    Button("venue_detail_location_view_on_map", action: onOpenOnMap)
                }
                if let email = venue.email, !email.isEmpty, let url = URL(string: "mailto:\(email)") {
                    Button { openURL(url) } label: { Label { Text(verbatim: email) } icon: { Image(systemName: "envelope") } }
                }
            }
        }
    }
}

/** 桌台：活动类型切换，选中类型的桌台数 / 起步价或每场价格，桌台 / 游戏库 / 主题 / 剧本，再是退款政策。 */
struct VenueActivityTypesSection: View {
    let model: VenueDetailModel

    @Environment(\.locale) private var locale

    var body: some View {
        Section("venue_detail_sections_activity_types") {
            if model.activityTypes.isEmpty {
                Text("venue_detail_no_activity_types").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.activityTypes, id: \.self) { activityType in
                            let isOn = activityType == model.activityType
                            Button { model.selectActivityType(activityType) } label: {
                                Label { Text(activityType.kind.labelKey) } icon: {
                                    Image(activityType.kind.iconAsset).resizable().scaledToFit().frame(width: 18, height: 18)
                                }
                                .font(.subheadline.weight(isOn ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .foregroundStyle(isOn ? Color.white : Color.primary)
                                .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        if let activityType = model.activityType {
            if model.sessionEntries[activityType] != nil || activityType == .escapeRoom || activityType == .scriptMurder {
                sessionContent(activityType)
            } else {
                spaceContent(activityType)
            }
        }
    }

    @ViewBuilder
    private func spaceContent(_ activityType: VenueActivityType) -> some View {
        let entry = model.spaceEntries[activityType]
        let summary = model.venue.data?.activityTypeEntries.first { $0.activityType == activityType }
        let currency = entry?.data?.currency ?? model.venue.data?.currency ?? ""
        let count = entry?.data?.spaceCount ?? summary?.spaceCount ?? 0
        let price = entry?.data?.minHourlyPriceAmount ?? summary?.minHourlyPriceAmount
        if count > 0 || price != nil {
            Section {
                HStack(spacing: 8) {
                    if count > 0 { VenueChip(text: localizedFormat("venue_detail_spaces", count), tone: RadixScale.slate.lightStep(9)) }
                    if let price { VenueChip(text: localizedFormat("venue_detail_from_price", formatMoney(price, currency: currency, locale: locale)), tone: RadixScale.slate.lightStep(9)) }
                }
            }
        }
        let spaces = (model.spaces[activityType] ?? []).filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
        if !spaces.isEmpty {
            Section("venue_detail_sections_spaces") {
                ForEach(spaces) { space in
                    SpaceRow(space: space, activityType: activityType, extras: model.spaceExtras[activityType]?[space.id] ?? [], currency: currency, imageURL: model.imageURL)
                }
            }
        }
        let titles = activityType == .boardGame ? model.boardGameTitles.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder } : []
        if !titles.isEmpty {
            Section("venue_detail_sections_titles") {
                ForEach(titles, id: \.id) { title in
                    CatalogRow(
                        name: title.name,
                        badge: Text(title.difficulty.labelKey),
                        chips: [
                            participantsLabel(minParticipants: title.playersMin, capacity: title.playersMax),
                            localizedFormat("venue_board_game_title_minutes", title.durationMinutes),
                        ],
                        priceChip: nil,
                        description: title.description,
                        coverURL: title.images.min { $0.sortOrder < $1.sortOrder }.flatMap { model.imageURL($0.imageId) }
                    )
                }
            }
        }
        Section("venue_detail_sections_refund") {
            if let entry = entry?.data {
                SpaceRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
            } else if entry?.error == nil {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func sessionContent(_ activityType: VenueActivityType) -> some View {
        let entry = model.sessionEntries[activityType]
        let currency = entry?.data?.currency ?? model.venue.data?.currency ?? ""
        if let data = entry?.data, data.minSessionPriceAmount != nil || data.bufferMinutes > 0 {
            Section {
                HStack(spacing: 8) {
                    if let price = data.minSessionPriceAmount {
                        VenueChip(text: localizedFormat("venue_session_per_session", formatMoney(price, currency: currency, locale: locale)), tone: RadixScale.slate.lightStep(9))
                    }
                    if data.bufferMinutes > 0 {
                        VenueChip(text: localizedFormat("venue_session_buffer", data.bufferMinutes), tone: RadixScale.slate.lightStep(9))
                    }
                }
            }
        }
        let options = (model.sessionOptions[activityType] ?? []).filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
        if !options.isEmpty {
            Section((activityType == .scriptMurder ? "venue_detail_sections_scripts" : "venue_detail_sections_themes") as LocalizedStringKey) {
                ForEach(options) { option in
                    CatalogRow(
                        name: option.name,
                        badge: Text(String(localized: option.difficulty.labelResource)),
                        chips: (activityType == .scriptMurder ? [option.subtitle].compactMap { $0 }.filter { !$0.isEmpty } : []) + [
                            localizedFormat("venue_session_minutes", option.durationMinutes),
                            participantsLabel(minParticipants: option.playersMin, capacity: option.playersMax),
                        ],
                        priceChip: localizedFormat("venue_session_per_session", formatMoney(option.priceAmount, currency: currency, locale: locale)),
                        description: option.description,
                        coverURL: option.images.min { $0.sortOrder < $1.sortOrder }.flatMap { model.imageURL($0.imageId) }
                    )
                }
            }
        }
        Section("venue_detail_sections_refund") {
            if let entry = entry?.data {
                SpaceRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
            } else if entry?.error == nil {
                ProgressView()
            }
        }
    }
}

/** 一张桌台 / 一间包间 / 一个机位：照片、名字、类型、人数，KTV 和台球还有自己的标签。 */
private struct SpaceRow: View {
    let space: SpaceUi
    let activityType: VenueActivityType
    let extras: [SpaceExtra]
    let currency: String
    let imageURL: (String?) -> URL?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityTypeCover(url: space.images.min { $0.sortOrder < $1.sortOrder }.flatMap { imageURL($0.imageId) }, activityType: activityType.kind, iconSize: 20)
                .frame(width: 64, height: 48)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: space.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                PulsoFlowLayout(spacing: 4) {
                    VenueChip(text: String(localized: space.kind.labelResource), tone: RadixScale.slate.lightStep(9))
                    VenueChip(text: participantsLabel(minParticipants: space.capacityMin, capacity: space.capacityMax), tone: RadixScale.slate.lightStep(9))
                    ForEach(extras, id: \.self) { extra in
                        switch extra {
                        case let .ktvRoomSize(size): VenueChip(text: String(localized: size.labelResource), tone: RadixScale.slate.lightStep(9))
                        case let .minSpend(amount): VenueChip(text: localizedFormat("venue_ktv_min_spend", formatMoney(amount, currency: currency, locale: locale)), tone: RadixScale.amber.lightStep(9))
                        case let .billiardsTable(type): VenueChip(text: String(localized: type.labelResource), tone: RadixScale.slate.lightStep(9))
                        }
                    }
                }
                if let description = space.description, !description.isEmpty {
                    Text(verbatim: description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

/** 游戏库里的一款桌游，或者密室主题 / 剧本：名字、难度、标签、价格和简介。 */
private struct CatalogRow: View {
    let name: String
    let badge: Text
    let chips: [String]
    let priceChip: String?
    let description: String?
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let coverURL {
                PulsoRemoteImage(url: coverURL)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
            }
            HStack {
                Text(verbatim: name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                badge
                    .font(.caption.weight(.medium))
                    .foregroundStyle(RadixScale.blue.lightStep(11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RadixScale.blue.lightStep(9).opacity(0.14), in: .capsule)
            }
            PulsoFlowLayout(spacing: 4) {
                ForEach(chips, id: \.self) { VenueChip(text: $0, tone: RadixScale.slate.lightStep(9)) }
                if let priceChip { VenueChip(text: priceChip, tone: RadixScale.green.lightStep(9)) }
            }
            if let description, !description.isEmpty {
                Text(verbatim: description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}

/** 预约须知：每个已上线活动类型的取消与退款规则，再是门店自己的说明。 */
struct VenuePoliciesSection: View {
    let model: VenueDetailModel
    let venue: VenueDetail

    var body: some View {
        if !model.activityTypes.isEmpty {
            Section("venue_detail_sections_refund") {
                ForEach(model.activityTypes, id: \.self) { activityType in
                    VStack(alignment: .leading, spacing: 6) {
                        Label { Text(activityType.kind.labelKey).font(.subheadline.weight(.semibold)) } icon: {
                            Image(activityType.kind.iconAsset).resizable().scaledToFit().frame(width: 18, height: 18)
                        }
                        if let entry = model.spaceEntries[activityType]?.data {
                            SpaceRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
                        } else if let entry = model.sessionEntries[activityType]?.data {
                            SpaceRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
        }
        if let instructions = venue.bookingInstructions, !instructions.trimmingCharacters(in: .whitespaces).isEmpty {
            Section("venue_detail_sections_instructions") { Text(verbatim: instructions).font(.subheadline) }
        }
    }
}

/** 会员（Android `VenueMembershipCard`）：我当前的卡（有效期）和在售等级，点开方案面板。 */
struct VenueMembershipSection: View {
    let model: VenueDetailModel
    let onOpenMine: (MyMembership) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let levels = levelsOnSale
        if model.activeMembership != nil || !levels.isEmpty {
            Section {
                if let active = model.activeMembership {
                    Button { onOpenMine(active) } label: {
                        HStack(spacing: 10) {
                            MembershipLevelBadge(icon: active.levelIcon, color: active.levelColor, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: active.levelName).font(.headline).foregroundStyle(Color.primary)
                                Text(verbatim: active.endsAt.map { localizedFormat("membership_valid_until", VenueTime.date($0, timezone: active.venueTimezone, locale: locale)) } ?? String(localized: "membership_lifetime"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                }
                ForEach(levels, id: \.id) { level in
                    HStack(spacing: 10) {
                        MembershipLevelBadge(icon: level.icon, color: level.color, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(verbatim: level.name).font(.subheadline.weight(.semibold))
                                if level.id == model.activeMembership?.levelId {
                                    VenueChip(text: String(localized: "venue_membership_current"), tone: Color.accentColor)
                                }
                            }
                            Text(verbatim: level.discountPercent > 0
                                ? localizedFormat("membership_discount", String(level.discountPercent), bookingDiscountZhe(level.discountPercent))
                                : String(localized: "membership_no_discount"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !levels.isEmpty {
                    Button((model.activeMembership != nil ? "venue_membership_card_change" : "venue_membership_card_view_plans") as LocalizedStringKey) {
                        model.openMembershipSheet()
                    }
                }
            } header: {
                Text("venue_membership_title")
            } footer: {
                Text("venue_membership_card_all_activity_types")
            }
        }
    }

    /** 上架方案里的等级，按等级排。 */
    private var levelsOnSale: [MembershipLevel] {
        (model.offers.data?.levels ?? []).filter { level in model.shownOffers.contains { $0.levelId == level.id } }.sorted { $0.rank < $1.rank }
    }
}

/** 商品与服务（Android `VenueOfferingGrid`）：只能到店买。 */
struct VenueOfferingsSection: View {
    let offerings: [VenueOffering]
    let imageURL: (String?) -> URL?

    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            ForEach(offerings, id: \.id) { offering in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Color(.tertiarySystemFill)
                        if let url = imageURL(offering.images.min { $0.sortOrder < $1.sortOrder }?.imageId) {
                            PulsoRemoteImage(url: url)
                        } else {
                            Image(systemName: offering.type == .product ? "bag" : "hand.raised").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: offering.name).font(.subheadline.weight(.semibold))
                        HStack(spacing: 6) {
                            Text(offering.type.labelKey)
                            Text(verbatim: "·")
                            Text(offering.availabilityStatus.labelKey)
                            if let minutes = offering.durationMinutes {
                                Text(verbatim: "· " + localizedFormat("venue_detail_offerings_duration", String(minutes)))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let brand = [offering.brand, offering.model].compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " ").nilIfEmpty {
                            Text(verbatim: brand).font(.caption).foregroundStyle(.secondary)
                        }
                        if let description = offering.description, !description.isEmpty {
                            Text(verbatim: description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                    if let price = offering.priceAmount {
                        Text(verbatim: formatMoney(price, currency: offering.currency, locale: locale)).font(.subheadline.monospacedDigit())
                    }
                }
            }
        } header: {
            Text("venue_detail_sections_offerings")
        } footer: {
            Text("venue_detail_offerings_at_venue")
        }
    }
}

/** 成员在这栋建筑办的活动：即将开始 / 历史（门店详情和建筑详情共用）。 */
struct BuildingActivitiesSection: View {
    let activities: BuildingActivities
    let imageURL: (String?) -> URL?
    let onRetry: () -> Void

    var body: some View {
        Section {
            PulsoHighlightTabRow([BuildingActivityFilter.upcoming, .history], selection: Binding(get: { activities.filter }, set: { activities.select($0) })) { filter in
                Text(filter == .upcoming ? "building_detail_activities_upcoming" : "building_detail_activities_history")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            if let rows = activities.activities.data, !rows.isEmpty {
                ForEach(rows) { row in
                    NavigationLink(value: NearRoute.activity(activityType: row.item.activityType, activityId: row.item.id)) {
                        ActivityFeedCard(item: row.item, imageURL: imageURL(row.item.coverImageId))
                    }
                }
            } else if activities.activities.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = activities.activities.error {
                PulsoLoadErrorView(error, retry: onRetry)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text((activities.filter == .upcoming ? "building_detail_activities_empty" : "building_detail_activities_history_empty") as LocalizedStringKey)
                        .font(.subheadline.weight(.semibold))
                    Text((activities.filter == .upcoming ? "building_detail_activities_empty_body" : "building_detail_activities_history_empty_body") as LocalizedStringKey)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("venue_detail_sections_activities")
        }
    }
}

