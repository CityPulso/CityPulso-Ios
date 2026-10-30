import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

extension TournamentEntryStatus {
    /** 这条报名不再占名额（退出、主办方取消、没付款过期）。 */
    var isEnded: Bool { self == .withdrawn || self == .canceled || self == .expired }
}

/** 我的赛事（Android `MyTournamentsViewModel`）：组队邀请、我的报名、获得的奖品；回复 / 付款 / 退出后经球馆事件重拉。 */
@MainActor
@Observable
final class MyTournamentsModel {
    static let withdrawable: Set<TournamentEntryStatus> = [.forming, .pending, .awaitingPayment, .waitlisted]

    var tab = MyTournamentsTab.entries
    var entryFilter = MyEntriesFilter.active
    /** 我的报名和组队邀请一起分页，页面按标签过滤。 */
    let allEntries: PagedList<TournamentEntry, Int>
    let prizes: PagedList<TournamentGrant, Int>
    private(set) var busyId: String?

    @ObservationIgnored @Injected(\.tournamentService) private var tournamentService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore

    init() {
        let service = Container.shared.tournamentService()
        allEntries = service.pageMyEntries()
        prizes = service.pageMyPrizes()
    }

    var profileId: String { sessionStore.state.value.currentProfileId }

    /** 别人的队伍邀请了我，还没回复。 */
    func isInvited(_ entry: TournamentEntry) -> Bool {
        entry.members.contains { $0.profileId == profileId && $0.status == .invited }
    }

    func isCaptain(_ entry: TournamentEntry) -> Bool { entry.captainProfileId == profileId }

    /** 我在的报名（队长或已接受），按 [entryFilter] 分进行中 / 已结束。 */
    var entries: [TournamentEntry] {
        allEntries.items.filter { !isInvited($0) && $0.status.isEnded == (entryFilter == .ended) }
    }

    var invitations: [TournamentEntry] { allEntries.items.filter(isInvited) }

    func observe() async {
        await concurrently([
            { await self.allEntries.observe() },
            { await self.prizes.observe() },
        ])
    }

    func refresh() async {
        async let a: Void = allEntries.refresh()
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

/**
 * 我的赛事（Android `MyTournamentsScreen`，设计 `.pictures/design/tournaments`）：我的报名、组队邀请（红色数字）、获得的奖品三个标签；
 * 邀请卡下面是两个等宽按钮「加入队伍」「拒绝」。
 */
struct MyTournamentsView: View {
    @State private var model = MyTournamentsModel()
    @State private var withdrawing: PulsoHoldConfirm?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Text("tournament_mine_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            Section {
                switch model.tab {
                case .entries: entryRows
                case .invitations: invitationRows
                case .prizes: prizeRows
                }
            } header: {
                tabs
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .navigationTitle("tournament_mine_title")
        .refreshable { await model.refresh() }
        .task { await model.observe() }
        .pulsoHoldConfirm($withdrawing)
    }

    /** 三个标签（图标 + 名字，邀请带红色数字）；「我的报名」下面再分进行中 / 已结束。 */
    private var tabs: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(MyTournamentsTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            if model.tab == .entries {
                Picker("tournament_mine_entries", selection: $model.entryFilter) {
                    Text("tournament_mine_filter_active").tag(MyEntriesFilter.active)
                    Text("tournament_mine_filter_ended").tag(MyEntriesFilter.ended)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .listRowInsets(EdgeInsets())
        .textCase(nil)
    }

    private func tabButton(_ tab: MyTournamentsTab) -> some View {
        let selected = model.tab == tab
        let count = tab == .invitations ? model.invitations.count : 0
        return Button { model.tab = tab } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: tab.symbol)
                    Text(tab.labelKey).lineLimit(1).minimumScaleFactor(0.8)
                    if count > 0 {
                        Text(verbatim: "\(count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .background(.red, in: .capsule)
                    }
                }
                .font(.subheadline.weight(selected ? .semibold : .regular))
                Capsule().fill(selected ? Color.accentColor : .clear).frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /* ------------------------------ 我的报名 ------------------------------ */

    @ViewBuilder
    private var entryRows: some View {
        let list = model.allEntries
        let rows = model.entries
        if list.isLoading {
            skeletons
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if rows.isEmpty, list.endReached {
            ContentUnavailableView {
                Text("tournament_mine_empty")
            } description: {
                Text("tournament_mine_empty_body")
            } actions: {
                Button("tournament_mine_browse") { shell?.open(.explore) }.buttonStyle(.glassProminent)
            }
        } else {
            ForEach(rows, id: \.id) { entry in
                let captain = model.isCaptain(entry)
                let pay = captain && entry.status == .awaitingPayment
                let withdraw = captain && MyTournamentsModel.withdrawable.contains(entry.status)
                EntryCard(entry: entry, line: entryLine(entry), busy: model.busyId == entry.id, showActions: pay || withdraw) {
                    if pay {
                        Button { Task { await model.pay(entry.id) } } label: { Text("tournament_mine_pay").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                    }
                    if withdraw {
                        Button {
                            withdrawing = PulsoHoldConfirm(
                                title: String(localized: "tournament_mine_withdraw_title"),
                                message: String(localized: "tournament_mine_withdraw_body"),
                                label: String(localized: "tournament_mine_withdraw")
                            ) { Task { await model.withdraw(entry.id) } }
                        } label: { Text("tournament_mine_withdraw").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                    }
                }
            }
            moreFooter(list)
        }
    }

    private func entryLine(_ entry: TournamentEntry) -> String {
        [
            entry.divisionName.isEmpty ? nil : entry.divisionName,
            entry.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            String(localized: entry.status.labelResource),
            entry.amount > 0 ? formatMoney(entry.amount, currency: entry.currency, locale: locale) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /* ------------------------------ 组队邀请 ------------------------------ */

    @ViewBuilder
    private var invitationRows: some View {
        let list = model.allEntries
        let rows = model.invitations
        if list.isLoading {
            skeletons
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if rows.isEmpty, list.endReached {
            ContentUnavailableView { Text("tournament_mine_invitations_empty") }
        } else {
            ForEach(rows, id: \.id) { entry in
                // 「加入 Ethan & Olivia · 公开双打」：队里其他人，再是组别。
                let team = entry.members.filter { $0.profileId != model.profileId }
                    .compactMap { $0.displayName?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " & ")
                EntryCard(
                    entry: entry,
                    line: localizedFormat("tournament_mine_invite_line", team.isEmpty ? (entry.name ?? "") : team, entry.divisionName),
                    busy: model.busyId == entry.id,
                    showActions: true
                ) {
                    Button { Task { await model.answer(entry.id, accept: true) } } label: { Text("tournament_mine_accept").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                    Button { Task { await model.answer(entry.id, accept: false) } } label: { Text("tournament_mine_decline").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                }
            }
            moreFooter(list)
        }
    }

    /* ------------------------------ 奖品 ------------------------------ */

    @ViewBuilder
    private var prizeRows: some View {
        let list = model.prizes
        if list.isLoading {
            skeletons
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            ContentUnavailableView { Text("tournament_mine_prizes_empty") }
        } else {
            ForEach(list.items, id: \.id) { grant in
                prizeCard(grant)
                    .onAppear { if grant.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }

    private func prizeCard(_ grant: TournamentGrant) -> some View {
        let what = grant.prizeType == .cash && grant.cashAmount != nil
            ? formatMoney(grant.cashAmount!, currency: grant.currency ?? "", locale: locale)
            : grant.prizeTitle
        return HStack(spacing: 12) {
            Image(systemName: "gift").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: grant.quantity > 1 ? "\(what) ×\(grant.quantity)" : what).font(.headline)
                Text(verbatim: [grant.tournamentTitle, grant.awardName, String(localized: grant.prizeType.labelResource), String(localized: grant.status.labelResource)].joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /* ------------------------------ 公用 ------------------------------ */

    private var skeletons: some View {
        ForEach(0 ..< 3, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 16).fill(.fill.tertiary).frame(height: 132)
        }
    }

    /** 报名和邀请从同一份分页里过滤：列表底部出现时就再拉一页，过滤后行很少也能翻下去。 */
    @ViewBuilder
    private func moreFooter(_ list: PagedList<TournamentEntry, Int>) -> some View {
        if !list.endReached {
            ProgressView().frame(maxWidth: .infinity).onAppear { list.loadMore() }
        }
    }
}

/** 赛事名、一行摘要、开始时间、队员 / 付款提示，最后是等宽按钮。 */
private struct EntryCard<Actions: View>: View {
    let entry: TournamentEntry
    let line: String
    let busy: Bool
    let showActions: Bool
    @ViewBuilder let actions: () -> Actions
    @Environment(\.locale) private var locale

    var body: some View {
        let accepted = entry.members.count { $0.status == .accepted }
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: LoopRoute.tournament(tournamentId: entry.tournamentId)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.tournamentTitle).font(.headline).lineLimit(2)
                    if !line.isEmpty { muted(line) }
                    if let starts = DateTimeFormatters.monthDayTime(entry.tournamentStartsAt, locale: locale) {
                        Label { muted(starts) } icon: { Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary) }
                    }
                    if entry.maxMembers > 1, entry.status != .canceled {
                        muted(localizedFormat("tournament_mine_roster", accepted, entry.maxMembers, entry.members.map { $0.displayName ?? String($0.profileId.prefix(6)) }.joined(separator: ", ")))
                    }
                    if entry.status == .canceled, let reason = entry.cancelReason, !reason.isEmpty {
                        muted(localizedFormat("tournament_mine_canceled_reason", reason))
                    }
                    if entry.status == .forming {
                        Text(verbatim: localizedFormat("tournament_mine_forming_hint", entry.minMembers)).font(.caption).foregroundStyle(.orange)
                    }
                    if entry.status == .awaitingPayment, let expires = entry.expiresAt {
                        Text(verbatim: localizedFormat("tournament_mine_pay_by", DateTimeFormatters.monthDayTime(expires, locale: locale) ?? "")).font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationLinkIndicatorVisibility(.hidden)
            if showActions {
                HStack(spacing: 8) { actions() }
                    .padding(.top, 8)
                    .disabled(busy)
                    .overlay { if busy { ProgressView() } }
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func muted(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
    }
}

extension MyTournamentsTab {
    var labelKey: LocalizedStringKey {
        switch self {
        case .entries: "tournament_mine_entries"
        case .invitations: "tournament_mine_invitations"
        case .prizes: "tournament_mine_prizes"
        }
    }

    var symbol: String {
        switch self {
        case .entries: "ticket"
        case .invitations: "person.badge.plus"
        case .prizes: "gift"
        }
    }
}
