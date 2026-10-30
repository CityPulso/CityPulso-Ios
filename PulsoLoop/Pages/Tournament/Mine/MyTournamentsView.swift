import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 我的赛事（Android `MyTournamentsViewModel`）：我的报名和要回复的组队邀请、获得的奖品，都分页；回复 / 付款 / 退出后经球馆事件重拉。 */
@MainActor
@Observable
final class MyTournamentsModel {
    static let withdrawable: Set<TournamentEntryStatus> = [.forming, .pending, .awaitingPayment, .waitlisted]

    let entries: PagedList<TournamentEntry, Int>
    let prizes: PagedList<TournamentGrant, Int>
    private(set) var busyId: String?

    @ObservationIgnored @Injected(\.tournamentService) private var tournamentService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore

    init() {
        let service = Container.shared.tournamentService()
        entries = service.pageMyEntries()
        prizes = service.pageMyPrizes()
    }

    private var profileId: String { sessionStore.state.value.currentProfileId }

    /** 别人的队伍邀请了我，还没回复。 */
    func isInvited(_ entry: TournamentEntry) -> Bool {
        entry.members.contains { $0.profileId == profileId && $0.status == .invited }
    }

    func isCaptain(_ entry: TournamentEntry) -> Bool { entry.captainProfileId == profileId }

    func observe() async {
        await concurrently([
            { await self.entries.observe() },
            { await self.prizes.observe() },
        ])
    }

    func refresh() async {
        async let a: Void = entries.refresh()
        async let b: Void = prizes.refresh()
        _ = await (a, b)
    }

    func answer(_ entryId: String, accept: Bool) async {
        await act(entryId) { try await self.tournamentService.answer(entryId: entryId, accept: accept) }
    }

    func withdraw(_ entryId: String) async {
        await act(entryId) { try await self.tournamentService.withdraw(entryId: entryId) }
    }

    /** 待付款 / 候补转正：重新取付款意图，弹付款面板。 */
    func pay(_ entryId: String) async {
        await act(entryId) {
            let change = try await self.tournamentService.pay(entryId: entryId)
            guard let secret = change.clientSecret, let account = change.providerAccountId, let key = change.publishableKey else { return }
            switch await ConnectedPaymentSheet.present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret)) {
            case .completed: self.tournamentService.invalidate()
            case .canceled: break
            case let .failed(message): PulsoMessageCenter.shared.error(text: message)
            }
        }
    }

    private func act(_ id: String, _ block: @escaping () async throws -> Void) async {
        busyId = id
        defer { busyId = nil }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "program_action_failed")
        }
    }
}

/** 我的赛事（Android `MyTournamentsScreen`）：奖品横排在上面，下面是报名和组队邀请。 */
struct MyTournamentsView: View {
    @State private var model = MyTournamentsModel()
    @State private var withdrawing: TournamentEntry?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.locale) private var locale

    var body: some View {
        ProgramList(list: model.entries, observe: false, emptyTitle: "tournament_mine_empty", emptyBody: "tournament_mine_empty_body") {
            Button("tournament_mine_browse") { shell?.open(.explore) }.buttonStyle(.glassProminent)
        } header: {
            if !model.prizes.items.isEmpty {
                Section("tournament_mine_prizes") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(model.prizes.items, id: \.id) { grant in
                                prizeCard(grant)
                                    .onAppear { if grant.id == model.prizes.items.last?.id { model.prizes.loadMore() } }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                Text("tournament_mine_entries").font(.headline).listRowBackground(Color.clear)
            }
        } row: { entry in
            entryRow(entry)
        }
        .navigationTitle("tournament_mine_title")
        .task { await model.observe() }
        .sheet(item: $withdrawing) { entry in
            // 按住确认（Android `holdConfirm`）。
            VStack(alignment: .leading, spacing: 16) {
                Text("tournament_mine_withdraw_title").font(.title3.bold())
                Text("tournament_mine_withdraw_body").foregroundStyle(.secondary)
                PulsoHoldButton("tournament_mine_withdraw", loading: model.busyId == entry.id) {
                    Task {
                        await model.withdraw(entry.id)
                        withdrawing = nil
                    }
                }
            }
            .padding(24)
            .presentationDetents([.height(240)])
        }
    }

    private func entryRow(_ entry: TournamentEntry) -> some View {
        let invited = model.isInvited(entry)
        let captain = model.isCaptain(entry)
        let accepted = entry.members.count { $0.status == .accepted }
        return VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: LoopRoute.tournament(tournamentId: entry.tournamentId)) {
                VStack(alignment: .leading, spacing: 4) {
                    if invited { Text("tournament_mine_invitations").font(.caption.weight(.medium)).foregroundStyle(.orange) }
                    Text(verbatim: entry.tournamentTitle).font(.headline)
                    Text(verbatim: [
                        entry.divisionName,
                        entry.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                        String(localized: entry.status.labelResource),
                        DateTimeFormatters.monthDayTime(entry.tournamentStartsAt, locale: locale),
                        entry.amount > 0 ? formatMoney(entry.amount, currency: entry.currency, locale: locale) : nil,
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if entry.maxMembers > 1 {
                        Text(verbatim: localizedFormat("tournament_mine_roster", accepted, entry.maxMembers, entry.members.map { $0.displayName ?? String($0.profileId.prefix(6)) }.joined(separator: ", ")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.status == .canceled, let reason = entry.cancelReason, !reason.isEmpty {
                        Text(verbatim: localizedFormat("tournament_mine_canceled_reason", reason)).font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.status == .forming {
                        Text(verbatim: localizedFormat("tournament_mine_forming_hint", entry.minMembers)).font(.caption).foregroundStyle(.orange)
                    }
                    if entry.status == .awaitingPayment, let expires = entry.expiresAt {
                        Text(verbatim: localizedFormat("tournament_mine_pay_by", DateTimeFormatters.monthDayTime(expires, locale: locale) ?? "")).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                if invited {
                    Button("tournament_mine_accept") { Task { await model.answer(entry.id, accept: true) } }.buttonStyle(.glassProminent)
                    Button("tournament_mine_decline") { Task { await model.answer(entry.id, accept: false) } }.buttonStyle(.glass)
                } else {
                    if captain, entry.status == .awaitingPayment {
                        Button("tournament_mine_pay") { Task { await model.pay(entry.id) } }.buttonStyle(.glassProminent)
                    }
                    if captain, MyTournamentsModel.withdrawable.contains(entry.status) {
                        Button("tournament_mine_withdraw") { withdrawing = entry }.buttonStyle(.glass)
                    }
                }
                if model.busyId == entry.id { ProgressView() }
            }
            .disabled(model.busyId == entry.id)
        }
    }

    private func prizeCard(_ grant: TournamentGrant) -> some View {
        let what = grant.prizeType == .cash && grant.cashAmount != nil
            ? formatMoney(grant.cashAmount!, currency: grant.currency ?? "", locale: locale)
            : grant.prizeTitle
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: grant.quantity > 1 ? "\(what) ×\(grant.quantity)" : what).fontWeight(.medium)
            Text(verbatim: [grant.tournamentTitle, grant.awardName, String(localized: grant.prizeType.labelResource), String(localized: grant.status.labelResource)].joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
    }
}

extension TournamentEntry: Identifiable {}
