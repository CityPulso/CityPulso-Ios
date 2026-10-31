import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* 球馆详情各分段（Android `VenueDetailOverview` / `VenueDetailSections` / `VenuePrograms` 和会员 / 时长包卡片）。 */

/** 概览：简介（展开 / 收起）、各运动场地数、设施，营业时间，位置（距离 + 地图预览 + 在地图上看）。 */
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
        if !about.isEmpty || !venue.sportEntries.isEmpty || !venue.amenities.isEmpty {
            Section("venue_detail_sections_about") {
                if !about.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: about).font(.subheadline).lineLimit(expanded ? nil : 4)
                        Button((expanded ? "venue_detail_read_less" : "venue_detail_read_more") as LocalizedStringKey) { expanded.toggle() }
                            .font(.footnote)
                            .buttonStyle(.borderless)
                    }
                }
                if !venue.sportEntries.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(venue.sportEntries, id: \.sport) { entry in
                            HStack(spacing: 8) {
                                Image(entry.sport.loopSport.iconAsset).resizable().scaledToFit().frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(entry.sport.loopSport.labelKey).font(.subheadline.weight(.medium))
                                    if entry.courtCount > 0 {
                                        Text(verbatim: localizedFormat("venue_detail_courts", entry.courtCount)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
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
                    LoopMapView(map: map, initialCenter: (lat, lng), initialZoom: 15, camera: MapCameraRequest(id: 1, latitude: lat, longitude: lng, zoom: 15))
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

/** 场地：运动切换，选中运动的场地数、起步价、每块场地和退款政策。 */
struct VenueSportsSection: View {
    let model: VenueDetailModel

    @Environment(\.locale) private var locale

    var body: some View {
        Section("venue_detail_sections_sports") {
            if model.sports.isEmpty {
                Text("venue_detail_no_sports").font(.subheadline).foregroundStyle(.secondary)
            } else if model.sports.count > 1 {
                Picker(selection: Binding(get: { model.sport ?? model.sports[0] }, set: { model.selectSport($0) })) {
                    ForEach(model.sports, id: \.self) { Text($0.loopSport.labelKey).tag($0) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
        }
        if let sport = model.sport {
            let entry = model.entries[sport]
            Section {
                HStack(spacing: 8) {
                    let count = entry?.data?.courtCount ?? model.venue.data?.sportEntries.first { $0.sport == sport }?.courtCount ?? 0
                    if count > 0 { VenueChip(text: localizedFormat("venue_detail_courts", count), tone: RadixScale.slate.lightStep(9)) }
                    if let price = entry?.data?.minHourlyPriceAmount {
                        Text(verbatim: localizedFormat("venue_detail_from_price", formatMoney(price, currency: entry?.data?.currency ?? model.venue.data?.currency ?? "", locale: locale)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            let courts = (model.courts[sport] ?? []).filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
            if !courts.isEmpty {
                Section("venue_detail_sections_courts") {
                    ForEach(courts) { court in
                        HStack(spacing: 12) {
                            SportCover(url: court.images.min { $0.sortOrder < $1.sortOrder }.flatMap { model.imageURL($0.imageId) }, sport: sport.loopSport, iconSize: 20)
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: court.name).font(.subheadline.weight(.semibold))
                                Text(court.surface.labelKey).font(.caption).foregroundStyle(.secondary)
                                if let description = court.description, !description.isEmpty {
                                    Text(verbatim: description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            Section("venue_detail_sections_refund") {
                if let entry = entry?.data {
                    CourtRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
                } else if entry?.error == nil {
                    ProgressView()
                }
            }
        }
    }
}

/** 订场须知：每个已上线运动的取消与退款规则，再是球馆自己的说明。 */
struct VenuePoliciesSection: View {
    let model: VenueDetailModel
    let venue: VenueDetail

    var body: some View {
        if !model.sports.isEmpty {
            Section("venue_detail_sections_refund") {
                ForEach(model.sports, id: \.self) { sport in
                    if let entry = model.entries[sport]?.data {
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(sport.loopSport.labelKey).font(.subheadline.weight(.semibold)) } icon: {
                                Image(sport.loopSport.iconAsset).resizable().scaledToFit().frame(width: 18, height: 18)
                            }
                            CourtRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
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
                Text("venue_membership_card_all_sports")
            }
        }
    }

    /** 上架方案里的等级，按等级排。 */
    private var levelsOnSale: [MembershipLevel] {
        (model.offers.data?.levels ?? []).filter { level in model.shownOffers.contains { $0.levelId == level.id } }.sorted { $0.rank < $1.rank }
    }
}

/** 预付时长包（Android `VenueBundleCard`）：我在这家还有多少，在售的包横排。 */
struct VenueBundleSection: View {
    let model: VenueBundleModel
    let onOpenMine: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        if !model.shownOffers.isEmpty || model.heldMinutes > 0 {
            Section {
                if model.heldMinutes > 0 {
                    Button(action: onOpenMine) {
                        Label { Text(verbatim: localizedFormat("venue_bundle_held", formatBundleHours(model.heldMinutes, locale: locale))) } icon: { Image(systemName: "ticket") }
                    }
                }
                if !model.shownOffers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.shownOffers, id: \.id) { offer in
                                BundleOfferTicket(offer: offer, hourlyPrice: model.hourlyPrice) { model.openSheet(offer.id) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    Button("venue_bundle_view_offers") { model.openSheet() }
                }
            } header: {
                Text("venue_bundle_title")
            } footer: {
                Text("venue_bundle_subtitle")
            }
        }
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

/** 在本馆举办的赛事，分页。 */
struct VenueTournamentsSection: View {
    let programs: VenueProgramsModel
    let imageURL: (String?) -> URL?

    @Environment(\.locale) private var locale

    var body: some View {
        Section("venue_programs_tournaments") {
            ForEach(programs.tournaments.items, id: \.id) { tournament in
                NavigationLink(value: LoopRoute.tournament(tournamentId: tournament.tournamentId)) {
                    ProgramRow(
                        title: tournament.title,
                        lines: [String(localized: tournament.status.labelResource) + " · " + (DateTimeFormatters.monthDayTime(tournament.startsAt, locale: locale) ?? "")],
                        coverURL: imageURL(tournament.coverImageId)
                    )
                }
                .onAppear { if tournament.id == programs.tournaments.items.last?.id { programs.tournaments.loadMore() } }
            }
        }
    }
}

/** 本馆的课程。 */
struct VenueCoursesSection: View {
    let programs: VenueProgramsModel
    let imageURL: (String?) -> URL?

    @Environment(\.locale) private var locale

    var body: some View {
        Section("venue_programs_courses") {
            ForEach(programs.courses, id: \.id) { course in
                NavigationLink(value: LoopRoute.course(courseId: course.id)) {
                    ProgramRow(
                        title: course.title,
                        lines: [
                            course.nextSessionAt.map { localizedFormat("venue_programs_next", DateTimeFormatters.monthDayTime($0, locale: locale) ?? "") },
                            localizedFormat("venue_programs_course_meta", course.sessionCount, formatMoney(course.priceAmount, currency: course.currency, locale: locale)),
                            localizedFormat("venue_programs_seats", max(0, course.capacity - course.enrolledCount - course.heldCount)),
                        ].compactMap { $0 },
                        coverURL: imageURL(course.coverImageId)
                    )
                }
            }
        }
    }
}

/** 本馆的教练；我是教练时还有申请合作。 */
struct VenueCoachesSection: View {
    let programs: VenueProgramsModel
    let imageURL: (String?) -> URL?

    @State private var message = ""

    var body: some View {
        Section("venue_programs_coaches") {
            ForEach(programs.coaches, id: \.id) { coach in
                NavigationLink(value: LoopRoute.coach(profileId: coach.coachProfileId)) {
                    ProgramRow(
                        title: coach.displayName ?? "",
                        lines: [[coach.certified ? String(localized: "venue_programs_certified") : nil, coach.headline].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty },
                        coverURL: imageURL(coach.avatarImageId)
                    )
                }
            }
        }
        if programs.isCoach {
            Section("venue_programs_coach_title") {
                switch programs.applyState {
                case .partner:
                    Text("venue_programs_coach_partner").font(.subheadline)
                    NavigationLink("venue_programs_coach_panel", value: LoopRoute.coachPanel)
                case .pending:
                    Text("venue_programs_coach_pending").font(.subheadline)
                    NavigationLink("venue_programs_coach_panel", value: LoopRoute.coachPanel)
                case .closed:
                    Text("venue_programs_coach_closed").font(.subheadline).foregroundStyle(.secondary)
                case .available:
                    if let policy = programs.policy {
                        Text(verbatim: localizedFormat("venue_programs_coach_discount", 100 - policy.certifiedDiscountPercent, 100 - policy.partnerDiscountPercent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("venue_programs_coach_message", text: $message, axis: .vertical).lineLimit(2 ... 4)
                    Button {
                        Task { await programs.applyAsCoach(message) }
                    } label: {
                        if programs.applying { ProgressView() } else { Text("venue_programs_coach_apply") }
                    }
                    .disabled(programs.applying)
                }
            }
        }
    }
}

private struct ProgramRow: View {
    let title: String
    let lines: [String]
    let coverURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color(.tertiarySystemFill)
                if let coverURL { PulsoRemoteImage(url: coverURL) } else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.subheadline.weight(.semibold)).lineLimit(2)
                ForEach(lines, id: \.self) { Text(verbatim: $0).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

/** 球友在这栋建筑办的活动：即将开始 / 历史（球馆详情和建筑详情共用）。 */
struct BuildingEventsSection: View {
    let events: BuildingEvents
    let imageURL: (String?) -> URL?
    let onRetry: () -> Void

    var body: some View {
        Section {
            Picker(selection: Binding(get: { events.filter }, set: { events.select($0) })) {
                Text("building_detail_events_upcoming").tag(BuildingSessionFilter.upcoming)
                Text("building_detail_events_history").tag(BuildingSessionFilter.history)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            if let rows = events.events.data, !rows.isEmpty {
                ForEach(rows) { row in
                    NavigationLink(value: LoopRoute.event(sport: row.item.sport, eventId: row.item.id)) {
                        EventFeedCard(item: row.item, imageURL: imageURL(row.item.coverImageId))
                    }
                }
            } else if events.events.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = events.events.error {
                PulsoLoadErrorView(error, retry: onRetry)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text((events.filter == .upcoming ? "building_detail_events_empty" : "building_detail_events_history_empty") as LocalizedStringKey)
                        .font(.subheadline.weight(.semibold))
                    Text((events.filter == .upcoming ? "building_detail_events_empty_body" : "building_detail_events_history_empty_body") as LocalizedStringKey)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("venue_detail_sections_sessions")
        }
    }
}

