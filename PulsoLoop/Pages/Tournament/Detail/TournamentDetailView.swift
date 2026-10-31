import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 赛事页（Android `TournamentDetailScreen`，设计 `.pictures/design/tournaments`）：顶部照片轮播（返回 / 分享 / ···），
 * 标题和状态，日期 · 球馆 · 组别和报名费，然后是 关于 | 组别 | 赛程 | 场地，底部固定「立即报名」或我的报名。
 */
struct TournamentDetailView: View {
    @State private var model: TournamentDetailModel
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(tournamentId: String) {
        _model = State(initialValue: TournamentDetailModel(tournamentId: tournamentId))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.tournament.data?.title ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { await model.observe() }
            .sheet(item: $model.sheet) { _ in
                if let currency = model.tournament.data?.currency {
                    TournamentRegisterSheet(model: model, currency: currency)
                }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let tournament = model.tournament.data {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(tournament)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("tournament_detail_share"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: LoopRoute.myTournaments) { Label("tournament_detail_open_mine", systemImage: "trophy") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(Text("tournament_detail_more"))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tournament = model.tournament.data {
            List {
                Section {
                    TournamentHero(urls: tournament.images.sorted { $0.sortOrder < $1.sortOrder }.compactMap { model.imageURL($0.imageId) })
                        .listRowInsets(EdgeInsets())
                    head(tournament)
                }
                if let outcome = model.outcome { outcomeSection(outcome) }
                Section {
                    tabSection(tournament)
                } header: {
                    tabBar
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .refreshable { await model.load() }
        } else if let error = model.tournament.error {
            if error.kind == .notFound {
                ContentUnavailableView("tournament_detail_not_found", systemImage: "trophy", description: Text("tournament_detail_not_found_body"))
            } else {
                PulsoLoadErrorView(error) { Task { await model.load() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /* ------------------------------ 头部 ------------------------------ */

    private var approvedVenues: [TournamentVenue] { model.tournament.data?.venues.filter { $0.status == .approved } ?? [] }

    private func dates(_ tournament: TournamentDetail) -> String {
        let zone = TimeZone(identifier: tournament.timezone) ?? .current
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: zone)
        var days: [String] = []
        for raw in [tournament.startsAt, tournament.endsAt] {
            if let day = DateTimeFormatters.parseInstant(raw)?.formatted(style), !days.contains(day) { days.append(day) }
        }
        return days.joined(separator: " – ")
    }

    /** 最低报名费「CA$40 起」（或免费）；没有组别时 nil。 */
    private func fee(_ currency: String) -> String? {
        guard let min = model.divisions.map(\.feeAmount).min() else { return nil }
        return min == 0 ? String(localized: "tournament_list_free_entry") : localizedFormat("tournament_list_from_fee", formatMoney(min, currency: currency, locale: locale))
    }

    private func shareText(_ tournament: TournamentDetail) -> String {
        [tournament.title, dates(tournament), approvedVenues.first?.venueName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /** 标题 + 状态，日期、球馆（点开）、组别 · 报名 · 报名费；草稿 / 已取消在下面说明。 */
    private func head(_ tournament: TournamentDetail) -> some View {
        let divisions = model.divisions
        let entries = divisions.reduce(0) { $0 + $1.registeredCount }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(verbatim: tournament.title).font(.title2.bold())
                Spacer(minLength: 0)
                TournamentStatusChip(status: tournament.status)
            }
            let day = dates(tournament)
            if !day.isEmpty { meta("calendar", day) }
            if let venue = approvedVenues.first {
                Button { shell?.push(LoopRoute.venue(venueId: venue.venueId, sheet: nil)) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(verbatim: venue.venueName).lineLimit(1)
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 16) {
                if !divisions.isEmpty {
                    meta("person.2", [localizedFormat("tournament_list_divisions", divisions.count), localizedFormat("tournament_list_entries", entries)].joined(separator: " · "))
                }
                if let fee = fee(tournament.currency) { meta("dollarsign.circle", fee) }
            }
            switch tournament.status {
            case .draft:
                Text("tournament_detail_draft").foregroundStyle(.orange)
            case .canceled:
                if let reason = tournament.cancelReason {
                    Text(verbatim: localizedFormat("tournament_detail_canceled_reason", reason)).foregroundStyle(.red)
                } else {
                    Text("tournament_detail_canceled").foregroundStyle(.red)
                }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TournamentDetailTab.allCases, id: \.self) { tab in
                let selected = model.tab == tab
                Button { model.tab = tab } label: {
                    VStack(spacing: 6) {
                        Text(tab.labelKey).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                        Capsule().fill(selected ? Color.accentColor : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(.bar)
        .listRowInsets(EdgeInsets())
        .textCase(nil)
    }

    @ViewBuilder
    private func tabSection(_ tournament: TournamentDetail) -> some View {
        switch model.tab {
        case .about:
            about(tournament)
            if let rules = tournament.rules, !rules.trimmingCharacters(in: .whitespaces).isEmpty {
                card {
                    Text("tournament_detail_rules").font(.headline)
                    Text(verbatim: rules).font(.footnote).foregroundStyle(.secondary)
                }
            }
            let awarded = model.divisions.filter { !$0.awards.isEmpty }
            if !awarded.isEmpty {
                Text("tournament_detail_prizes").font(.title3.weight(.semibold)).listRowSeparator(.hidden)
                ForEach(awarded, id: \.id) { division in card { prizes(division, currency: tournament.currency) } }
            }
            if !tournament.hostProfiles.isEmpty { hosts(tournament) }
            venuesSection(tournament)
        case .divisions:
            if model.divisions.isEmpty { muted("tournament_detail_no_divisions") }
            ForEach(model.divisions, id: \.id) { division in
                card { divisionRow(division, currency: tournament.currency) }
            }
        case .schedule:
            if let division = model.division {
                bracketSection(division)
            } else {
                bracketPending
            }
        case .venue:
            venuesSection(tournament)
        }
    }

    /** 「关于赛事」：简介，再是一张事实表（运动、赛制、组别、报名费、报名截止）。 */
    @ViewBuilder
    private func about(_ tournament: TournamentDetail) -> some View {
        let divisions = model.divisions
        let formats = divisions.map { String(localized: $0.format.labelResource) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let deadline = divisions.compactMap { division in DateTimeFormatters.parseInstant(division.registrationClosesAt).map { ($0, division.registrationClosesAt) } }
            .max { $0.0 < $1.0 }?.1
        Text("tournament_detail_about").font(.title3.weight(.semibold)).listRowSeparator(.hidden)
        if let description = tournament.description, !description.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(verbatim: description).foregroundStyle(.secondary).listRowSeparator(.hidden)
        }
        card {
            if !tournament.sports.isEmpty {
                infoRow("figure.badminton", "tournament_detail_info_sport", tournament.sports.map { String(localized: $0.loopSport.labelResource) }.joined(separator: " · "))
            }
            if !formats.isEmpty { infoRow("square.grid.2x2", "tournament_detail_info_format", formats.joined(separator: " · ")) }
            if !divisions.isEmpty {
                infoRow("person.2", "tournament_detail_info_divisions", "\(localizedFormat("tournament_list_divisions", divisions.count)) (\(divisions.map(\.name).joined(separator: ", ")))")
            }
            if let fee = fee(tournament.currency) { infoRow("dollarsign.circle", "tournament_detail_info_fee", fee) }
            if let deadline { infoRow("calendar.badge.checkmark", "tournament_detail_info_deadline", dateTime(deadline)) }
        }
    }

    private func infoRow(_ symbol: String, _ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            Text(label).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
            Text(verbatim: value).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    private func hosts(_ tournament: TournamentDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("tournament_detail_hosted_by").font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tournament.hostProfiles, id: \.profileId) { host in
                        HStack(spacing: 4) {
                            PulsoAvatar(url: model.imageURL(host.avatarImageId), size: 24, fallbackText: host.displayName.map { String($0.prefix(1)) })
                            Text(verbatim: host.displayName ?? "").font(.caption)
                        }
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    /* ------------------------------ 场地 ------------------------------ */

    /** 「比赛场地」：带编号针的地图，下面每个场地的编号、距离、地址、场地时段，「查看球馆」「导航」。 */
    @ViewBuilder
    private func venuesSection(_ tournament: TournamentDetail) -> some View {
        let venues = approvedVenues
        if !venues.isEmpty {
            Label("tournament_detail_venues", systemImage: "mappin.and.ellipse").font(.title3.weight(.semibold)).listRowSeparator(.hidden)
            card {
                NumberedVenuesMap(venues: venues, map: model.map)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 12))
                ForEach(Array(venues.enumerated()), id: \.element.id) { index, venue in
                    venueRow(index + 1, venue, slots: tournament.allocations.filter { $0.venueId == venue.venueId }.sorted { $0.startsAt < $1.startsAt })
                }
            }
        }
    }

    private func venueRow(_ number: Int, _ venue: TournamentVenue, slots: [TournamentSlot]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NumberPin(number: number)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: venue.venueName).font(.headline)
                    if let me = model.me {
                        Text(verbatim: localizedFormat("tournament_detail_distance", distanceLabel(haversineM(me.latitude, me.longitude, venue.locationLat, venue.locationLng))))
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                    }
                }
                if !venue.address.isEmpty { Text(verbatim: venue.address).font(.caption).foregroundStyle(.secondary) }
                ForEach(slots, id: \.id) { slot in
                    HStack(spacing: 6) {
                        if !slot.label.isEmpty {
                            Text(verbatim: slot.label).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.fill.tertiary, in: .capsule)
                        }
                        Text(verbatim: [
                            DateTimeFormatters.sessionDayClockRange(slot.startsAt, slot.endsAt, locale: locale),
                            localizedFormat("tournament_detail_courts", slot.courts.count),
                        ].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button { shell?.push(LoopRoute.venue(venueId: venue.venueId, sheet: nil)) } label: {
                        Label("tournament_detail_view_venue", systemImage: "storefront")
                    }
                    .buttonStyle(.pulso(.soft))
                    Button { directions(venue) } label: {
                        Label("tournament_detail_navigate", systemImage: "location")
                    }
                    .buttonStyle(.pulso(.soft))
                    .tint(.secondary)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    /** 交给系统地图导航（Android `geo:` intent）。 */
    private func directions(_ venue: TournamentVenue) {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(venue.locationLat),\(venue.locationLng)"),
            URLQueryItem(name: "q", value: venue.venueName),
        ]
        if let url = components.url { openURL(url) }
    }

    /* ------------------------------ 底部栏 ------------------------------ */

    /** 已经在这场赛事里有报名：显示我的状态和能做的事，不再出现「立即报名」。 */
    @ViewBuilder
    private var bottomBar: some View {
        if model.tournament.data != nil {
            if let mine = model.myEntry {
                let invited = model.myStatus(mine) == .invited
                let summary = [invited ? String(localized: "tournament_mine_invitations") : String(localized: mine.status.labelResource), mine.divisionName]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                VStack(alignment: .leading, spacing: 8) {
                    if invited {
                        Text(verbatim: summary).font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            Button { Task { await model.answer(accept: true) } } label: { Text("tournament_mine_accept").frame(maxWidth: .infinity) }
                                .buttonStyle(.pulso())
                            Button { Task { await model.answer(accept: false) } } label: { Text("tournament_mine_decline").frame(maxWidth: .infinity) }
                                .buttonStyle(.pulso(.soft))
                        }
                    } else {
                        HStack(spacing: 12) {
                            Text(verbatim: summary).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Spacer(minLength: 0)
                            if mine.captainProfileId == model.myProfileId, mine.status == .awaitingPayment {
                                Button("tournament_mine_pay") { Task { await model.payMine() } }.buttonStyle(.pulso())
                            } else {
                                NavigationLink("tournament_detail_view_entry", value: LoopRoute.myTournaments).buttonStyle(.pulso(.soft))
                            }
                        }
                    }
                }
                .disabled(model.busy)
                .controlSize(.large)
                .padding(16)
                .background(.bar)
            } else if !model.openDivisions.isEmpty {
                Button { model.registerNow() } label: { Text("tournament_detail_register_now").frame(maxWidth: .infinity) }
                    .buttonStyle(.pulso())
                    .controlSize(.large)
                    .padding(16)
                    .background(.bar)
            }
        }
    }

    /* ------------------------------ 其他 ------------------------------ */

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: symbol) }
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var bracketPending: some View {
        ContentUnavailableView("tournament_detail_no_bracket", systemImage: "list.bullet.rectangle", description: Text("tournament_detail_no_bracket_body"))
            .listRowSeparator(.hidden)
    }

    private func outcomeSection(_ outcome: TournamentEntryStatus) -> some View {
        Section {
            let message: LocalizedStringKey = switch outcome {
            case .registered: "tournament_detail_result_registered"
            case .waitlisted: "tournament_detail_result_waitlisted"
            case .forming: "tournament_detail_result_forming"
            case .awaitingPayment: "tournament_detail_result_awaiting_payment"
            default: "tournament_detail_result_pending"
            }
            Text(message)
            NavigationLink("tournament_detail_open_mine", value: LoopRoute.myTournaments)
            Button("tournament_detail_dismiss") { model.dismissOutcome() }
        }
    }

    private func divisionRow(_ division: TournamentDivision, currency: String) -> some View {
        let open = model.live && division.registrationOpen()
        let members = division.minMembers == division.maxMembers
            ? localizedFormat("tournament_detail_members_exact", division.maxMembers)
            : localizedFormat("tournament_detail_members_range", division.minMembers, division.maxMembers)
        let fee = division.feeAmount > 0 ? formatMoney(division.feeAmount, currency: currency, locale: locale) : String(localized: "tournament_free")
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: division.name).font(.headline)
            Text(verbatim: [String(localized: division.sport.loopSport.labelResource), String(localized: division.format.labelResource), members, fee].joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(verbatim: localizedFormat("tournament_detail_places", division.placesLeft, division.capacity, division.waitlistedCount))
                .font(.caption).foregroundStyle(.secondary)
            if !division.registrationClosesAt.isEmpty {
                Text(verbatim: localizedFormat("tournament_detail_closes", dateTime(division.registrationClosesAt))).font(.caption).foregroundStyle(.secondary)
            }
            if let note = division.eligibilityNote, !note.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
            }
            if let mine = model.myEntry, mine.divisionId == division.id {
                Text(verbatim: localizedFormat("tournament_detail_my_status", String(localized: mine.status.labelResource)))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
            } else if open {
                Button {
                    model.openRegister(division)
                } label: {
                    Text((division.placesLeft == 0 ? "tournament_join_waitlist" : "tournament_register") as LocalizedStringKey).frame(maxWidth: .infinity)
                }
                .buttonStyle(.pulso())
                .padding(.top, 4)
            } else if model.live {
                muted("tournament_detail_closed")
            }
        }
    }

    private func prizes(_ division: TournamentDivision, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: division.name).font(.subheadline.weight(.semibold))
            ForEach(division.awards.sorted { $0.sortOrder < $1.sortOrder }, id: \.id) { award in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: award.recipientCount > 1 ? localizedFormat("tournament_detail_award_count", award.name, award.recipientCount) : award.name)
                        .fontWeight(.medium)
                    if award.placements.isEmpty { muted("tournament_detail_award_empty") }
                    ForEach(award.placements, id: \.id) { placement in
                        Text(verbatim: placementText(placement, currency: currency)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func placementText(_ placement: TournamentPlacement, currency: String) -> String {
        let snapshot = placement.sourceSnapshot
        let what = placement.prizeType == .cash
            ? placement.cashAmount.map { formatMoney($0, currency: placement.currency ?? currency, locale: locale) } ?? placement.title
            : (placement.title.isEmpty ? snapshot?.title ?? "" : placement.title)
        let from = snapshot.flatMap { $0.venueName.isEmpty ? nil : $0.venueName }
        return [
            String(localized: placement.prizeType.labelResource),
            placement.quantity > 1 ? "\(what) ×\(placement.quantity)" : what,
            String(localized: placement.distribution.labelResource),
            from.map { localizedFormat("tournament_detail_sponsored_by", $0) },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func bracketSection(_ division: TournamentDivision) -> some View {
        if model.divisions.count > 1 {
            Picker(selection: Binding(get: { division.id }, set: { model.selectedDivisionId = $0 })) {
                ForEach(model.divisions, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
        }
        if !model.bracketLoaded {
            ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
        } else if let bracket = model.bracket {
            let tbd = String(localized: "tournament_detail_tbd")
            let labels = Dictionary(bracket.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let matches = bracket.matches.filter { $0.divisionId == division.id }.sorted { ($0.round, $0.position) < ($1.round, $1.position) }
            let stageNames = matches.map { stageName($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let standings = bracket.standings.filter { $0.divisionId == division.id }.sorted { $0.rankOrder < $1.rankOrder }
            if matches.isEmpty, standings.isEmpty { bracketPending }
            ForEach(stageNames, id: \.self) { stage in
                Text(verbatim: stage).font(.subheadline.weight(.semibold)).listRowSeparator(.hidden)
                ForEach(matches.filter { stageName($0) == stage }, id: \.id) { match in
                    card { matchRow(match, labels: labels, tbd: tbd) }
                }
            }
            if !standings.isEmpty {
                Text("tournament_detail_standings").font(.subheadline.weight(.semibold)).listRowSeparator(.hidden)
                ForEach(standings, id: \.id) { standing in
                    let name = standing.entryName.flatMap { $0.isEmpty ? nil : $0 } ?? tournamentEntryName(labels[standing.entryId], fallback: tbd)
                    Text(verbatim: "\(standing.rankLabel)  \(name)").listRowSeparator(.hidden)
                }
            }
        } else {
            bracketPending
        }
    }

    private func stageName(_ match: TournamentMatch) -> String {
        [match.stageName, match.groupName].compactMap { $0 }.joined(separator: " · ")
    }

    private func matchRow(_ match: TournamentMatch, labels: [String: TournamentEntryLabel], tbd: String) -> some View {
        let a = tournamentEntryName(match.entryAId.flatMap { labels[$0] }, fallback: tbd)
        let b = tournamentEntryName(match.entryBId.flatMap { labels[$0] }, fallback: tbd)
        let place = [match.venueName, match.courtName].compactMap { $0 }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "\(a)  vs  \(b)").fontWeight(.medium)
                Spacer()
                Text(verbatim: tournamentScoreLine(match.scores)).monospacedDigit()
            }
            Text(verbatim: [
                String(localized: match.status.labelResource),
                match.winnerEntryId.map { localizedFormat("tournament_detail_winner", tournamentEntryName(labels[$0], fallback: tbd)) },
                match.startsAt.map { dateTime($0) },
                place.isEmpty ? nil : place,
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dateTime(_ iso: String) -> String {
        DateTimeFormatters.monthDayTime(iso, locale: locale) ?? ""
    }

    private func muted(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.footnote).foregroundStyle(.secondary)
    }
}

/** 报名一个组别（Android `TournamentRegisterSheet`）：双打 / 团体填队名、从好友里选队友，再选付款方式。 */
private struct TournamentRegisterSheet: View {
    @Bindable var model: TournamentDetailModel
    let currency: String
    @Environment(\.locale) private var locale

    var body: some View {
        if let sheet = model.sheet {
            let division = sheet.division
            NavigationStack {
                Form {
                    Section {
                        if sheet.solo {
                            Text("tournament_register_solo")
                        } else {
                            Text(verbatim: localizedFormat("tournament_register_team", division.minMembers, division.maxMembers))
                        }
                        Text(verbatim: division.feeAmount > 0 ? formatMoney(division.feeAmount, currency: currency, locale: locale) : String(localized: "tournament_free"))
                            .font(.headline)
                    }
                    if !sheet.solo {
                        Section {
                            TextField("tournament_register_team_name", text: Binding(get: { model.sheet?.name ?? "" }, set: { model.sheet?.name = $0 }),
                                      prompt: Text("tournament_register_team_name_hint"))
                        }
                        Section {
                            if let friends = sheet.friends.data {
                                if friends.isEmpty {
                                    Text("tournament_register_no_friends").font(.footnote)
                                }
                                ForEach(friends, id: \.friendProfileId) { friend in
                                    let checked = sheet.teammates.contains(friend.friendProfileId)
                                    Button { model.toggleTeammate(friend.friendProfileId) } label: {
                                        HStack {
                                            Text(verbatim: friend.profile.displayName ?? String(friend.friendProfileId.prefix(8)))
                                            Spacer()
                                            Image(systemName: checked ? "checkmark.circle.fill" : "circle").foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                    .disabled(!checked && sheet.teammates.count >= sheet.maxTeammates)
                                }
                            } else if sheet.friends.error != nil {
                                Text("tournament_register_friends_failed").font(.footnote).foregroundStyle(.red)
                            } else {
                                ProgressView().frame(maxWidth: .infinity)
                            }
                        } header: {
                            HStack {
                                Text("tournament_register_teammates")
                                Spacer()
                                Text(verbatim: "\(sheet.teammates.count) / \(sheet.maxTeammates)")
                            }
                        } footer: {
                            Text("tournament_register_teammates_note")
                        }
                    }
                    if division.feeAmount > 0, let method = sheet.method, model.methods.count > 1 {
                        Section("tournament_register_payment") {
                            Picker(selection: Binding(get: { method }, set: { model.sheet?.method = $0 })) {
                                ForEach(model.methods, id: \.self) { Text($0.labelKey).tag($0) }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    if let error = sheet.error {
                        Text(verbatim: error).font(.footnote).foregroundStyle(.red)
                    }
                    Section {
                        Button {
                            Task { await model.register() }
                        } label: {
                            if sheet.submitting {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text((division.placesLeft == 0 ? "tournament_join_waitlist" : "tournament_register") as LocalizedStringKey).frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.pulso())
                        .disabled(!sheet.ready)
                        .listRowBackground(Color.clear)
                    }
                }
                .navigationTitle(Text(verbatim: localizedFormat("tournament_register_title", division.name)))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
    }
}

/** 照片轮播，右下角页码；没有照片显示奖杯（Android `PulsoHeroPager`）。 */
private struct TournamentHero: View {
    let urls: [URL]
    @State private var page = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                ZStack {
                    Rectangle().fill(.fill.tertiary)
                    Image(systemName: "trophy.fill").font(.system(size: 56)).foregroundStyle(.secondary)
                }
            } else {
                TabView(selection: $page) {
                    ForEach(urls.indices, id: \.self) { index in
                        PulsoRemoteImage(url: urls[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .bottomTrailing) {
                    if urls.count > 1 {
                        Text(verbatim: localizedFormat("event_detail_photo_counter", page + 1, urls.count))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .padding(12)
                    }
                }
            }
        }
        .frame(height: 260)
        .clipped()
    }
}

/** 进行中 / 已发布绿色，结束灰色，取消红色。 */
private struct TournamentStatusChip: View {
    let status: TournamentStatus

    var body: some View {
        let tint: Color = switch status {
        case .published, .inProgress: .green
        case .canceled: .red
        default: .gray
        }
        Text(status.labelKey)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: .capsule)
    }
}

/** 地图上和列表里的编号圆点。 */
private struct NumberPin: View {
    let number: Int

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.accentColor, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/** 赛事场地的地图：每个场地一个编号针，镜头框住全部（Android `NumberedPinsMap`，不可交互）。 */
private struct NumberedVenuesMap: View {
    let venues: [TournamentVenue]
    let map: ResolvedMapPreference
    @State private var projection = LoopMapProjection()

    var body: some View {
        let lats = venues.map(\.locationLat)
        let lngs = venues.map(\.locationLng)
        let center = ((lats.min()! + lats.max()!) / 2, (lngs.min()! + lngs.max()!) / 2)
        let span = max(lats.max()! - lats.min()!, lngs.max()! - lngs.min()!)
        let zoom = span < 0.005 ? 14 : max(3, 14 - log2(span / 0.005))
        LoopMapView(
            map: map,
            initialCenter: center,
            initialZoom: zoom,
            camera: MapCameraRequest(id: 1, latitude: center.0, longitude: center.1, zoom: zoom),
            projection: projection
        )
        .allowsHitTesting(false)
        .overlay {
            let _ = projection.version
            ForEach(Array(venues.enumerated()), id: \.element.id) { index, venue in
                if let point = projection.point(latitude: venue.locationLat, longitude: venue.locationLng) {
                    NumberPin(number: index + 1).position(point)
                }
            }
        }
    }
}

extension TournamentDetailTab {
    var labelKey: LocalizedStringKey {
        switch self {
        case .about: "tournament_detail_tab_about"
        case .divisions: "tournament_detail_tab_divisions"
        case .schedule: "tournament_detail_tab_schedule"
        case .venue: "tournament_detail_tab_venue"
        }
    }
}
