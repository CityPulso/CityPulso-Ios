import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 赛事页（Android `TournamentDetailScreen`）：海报、主办方、组别报名、奖品、对阵和排名、场馆。 */
struct TournamentDetailView: View {
    @State private var model: TournamentDetailModel
    @Environment(\.locale) private var locale

    init(tournamentId: String) {
        _model = State(initialValue: TournamentDetailModel(tournamentId: tournamentId))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.tournament.data?.title ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.observe() }
            .sheet(item: $model.sheet) { _ in
                if let currency = model.tournament.data?.currency {
                    TournamentRegisterSheet(model: model, currency: currency)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let tournament = model.tournament.data {
            List {
                head(tournament)
                if let outcome = model.outcome { outcomeSection(outcome) }
                Section("tournament_detail_divisions") {
                    if model.divisions.isEmpty { muted("tournament_detail_no_divisions") }
                    ForEach(model.divisions, id: \.id) { division in
                        divisionRow(division, currency: tournament.currency)
                    }
                }
                if let about = tournament.description, !about.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("tournament_detail_about") { Text(verbatim: about) }
                }
                if let rules = tournament.rules, !rules.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("tournament_detail_rules") { Text(verbatim: rules).font(.footnote).foregroundStyle(.secondary) }
                }
                let awarded = model.divisions.filter { !$0.awards.isEmpty }
                if !awarded.isEmpty {
                    Section("tournament_detail_prizes") {
                        ForEach(awarded, id: \.id) { prizes($0, currency: tournament.currency) }
                    }
                }
                if let division = model.division {
                    bracketSection(division)
                }
                let venues = tournament.venues.filter { $0.status == .approved }
                if !venues.isEmpty {
                    Section("tournament_detail_venues") {
                        ForEach(venues, id: \.id) { venue in
                            NavigationLink(value: LoopRoute.venue(venueId: venue.venueId, sheet: nil)) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: venue.venueName).fontWeight(.medium)
                                    if !venue.address.isEmpty { Text(verbatim: venue.address).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
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

    private func head(_ tournament: TournamentDetail) -> some View {
        Section {
            let cover = tournament.images.min { $0.sortOrder < $1.sortOrder }?.imageId
            ZStack {
                Rectangle().fill(.fill.tertiary)
                if let url = model.imageURL(cover) {
                    PulsoRemoteImage(url: url)
                } else {
                    Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .listRowInsets(EdgeInsets())
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: tournament.title).font(.title2.bold())
                Text(verbatim: "\(String(localized: tournament.status.labelResource)) · \(dateTime(tournament.startsAt)) – \(dateTime(tournament.endsAt))")
                    .font(.footnote).foregroundStyle(.secondary)
                if !tournament.sports.isEmpty {
                    Text(verbatim: tournament.sports.map { String(localized: $0.loopSport.labelResource) }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
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
                if !tournament.hostProfiles.isEmpty {
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
            }
        }
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
            if open {
                Button {
                    model.openRegister(division)
                } label: {
                    Text((division.placesLeft == 0 ? "tournament_join_waitlist" : "tournament_register") as LocalizedStringKey).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
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
        Section("tournament_detail_bracket") {
            if model.divisions.count > 1 {
                Picker(selection: Binding(get: { division.id }, set: { model.selectedDivisionId = $0 })) {
                    ForEach(model.divisions, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            if let bracket = model.bracket {
                let tbd = String(localized: "tournament_detail_tbd")
                let labels = Dictionary(bracket.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let matches = bracket.matches.filter { $0.divisionId == division.id }.sorted { ($0.round, $0.position) < ($1.round, $1.position) }
                let stageNames = matches.map { stageName($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                let standings = bracket.standings.filter { $0.divisionId == division.id }.sorted { $0.rankOrder < $1.rankOrder }
                if matches.isEmpty { muted("tournament_detail_no_bracket") }
                ForEach(stageNames, id: \.self) { stage in
                    Text(verbatim: stage).font(.subheadline.weight(.semibold))
                    ForEach(matches.filter { stageName($0) == stage }, id: \.id) { match in
                        matchRow(match, labels: labels, tbd: tbd)
                    }
                }
                if !standings.isEmpty {
                    Text("tournament_detail_standings").font(.subheadline.weight(.semibold))
                    ForEach(standings, id: \.id) { standing in
                        let name = standing.entryName.flatMap { $0.isEmpty ? nil : $0 } ?? tournamentEntryName(labels[standing.entryId], fallback: tbd)
                        Text(verbatim: "\(standing.rankLabel)  \(name)")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
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
                        .buttonStyle(.glassProminent)
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
