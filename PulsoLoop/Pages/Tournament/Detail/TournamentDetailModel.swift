import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI

/** 一个组别的报名面板：队名、从好友里选队友、付款方式（Android `RegisterSheetState`）。 */
struct TournamentRegisterState: Identifiable {
    let division: TournamentDivision
    var name = ""
    var teammates: [String] = []
    var friends = Loadable<[FriendItem]>()
    var method: TournamentPaymentMethod?
    var submitting = false
    /** 面板盖住了全局提示，错误写在面板里。 */
    var error: String?

    var id: String { division.id }
    var solo: Bool { division.format == .singles }
    var maxTeammates: Int { max(0, division.maxMembers - 1) }
    var minTeammates: Int { max(0, division.minMembers - 1) }
    var ready: Bool { teammates.count >= minTeammates && !submitting }
}

/**
 * 赛事详情（Android `TournamentDetailViewModel`）：赛事、对阵、我在这场里的报名、报名（平台付款走付款面板）、
 * 我的位置（场地离我多远）和地图样式。球馆有写操作就重拉。
 */
@MainActor
@Observable
final class TournamentDetailModel {
    private static let friendsPage = 100

    let tournamentId: String
    private(set) var tournament = Loadable<TournamentDetail>()
    private(set) var bracket: TournamentBracket?
    /** 对阵请求回来了（有没有抽签都算）；之前赛程页显示加载。 */
    private(set) var bracketLoaded = false
    var selectedDivisionId: String?
    var sheet: TournamentRegisterState?
    private(set) var outcome: TournamentEntryStatus?
    var tab = TournamentDetailTab.about
    /** 我在这场赛事里的报名（任何组别）。 */
    private(set) var myEntries: [TournamentEntry] = []
    private(set) var busy = false
    private(set) var me: PickedLocation?
    private(set) var map = ResolvedMapPreference()

    @ObservationIgnored @Injected(\.tournamentService) private var tournamentService
    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.venueEventBus) private var eventBus
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored @Injected(\.deviceLocationStore) private var deviceLocation
    @ObservationIgnored @Injected(\.preferenceService) private var preferenceService

    init(tournamentId: String) {
        self.tournamentId = tournamentId
    }

    var methods: [TournamentPaymentMethod] {
        guard let t = tournament.data else { return [] }
        return [t.acceptsPlatform ? .platform : nil, t.acceptsOffline ? .offline : nil, t.acceptsPhone ? .phone : nil].compactMap { $0 }
    }

    var live: Bool { tournament.data?.status == .published || tournament.data?.status == .inProgress }

    var divisions: [TournamentDivision] { (tournament.data?.divisions ?? []).sorted { $0.sortOrder < $1.sortOrder } }

    var division: TournamentDivision? { divisions.first { $0.id == selectedDivisionId } ?? divisions.first }

    var myProfileId: String { sessionStore.state.value.currentProfileId }

    func myStatus(_ entry: TournamentEntry) -> TournamentMemberStatus? {
        entry.members.first { $0.profileId == myProfileId }?.status
    }

    /** 还算数的报名（没退出 / 取消 / 过期，我被邀请或已在队里）。 */
    var myEntry: TournamentEntry? {
        myEntries.first { entry in
            !entry.status.isEnded && (myStatus(entry).map { [TournamentMemberStatus.invited, .accepted].contains($0) } ?? false)
        }
    }

    /** 现在能报名的组别；底部「立即报名」至少要有一个。 */
    var openDivisions: [TournamentDivision] { live ? divisions.filter { $0.registrationOpen() } : [] }

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        await concurrently([
            {
                await self.load()
                for await _ in self.eventBus.signals(where: { _ in true }) {
                    await self.load()
                }
            },
            {
                for await device in self.deviceLocation.location.values() {
                    self.me = device?.point
                }
            },
            {
                for await preference in self.preferenceService.preference.values() {
                    self.map = preference.map
                }
            },
        ])
    }

    func load() async {
        tournament.isLoading = true
        do {
            tournament = try await Loadable(data: tournamentService.tournament(tournamentId), isLoading: false)
        } catch {
            tournament = Loadable(data: tournament.data, isLoading: false, error: UiError(error))
        }
        if let entries = try? await tournamentService.myEntriesIn(tournamentId) { myEntries = entries }
        // 抽签以后才有对阵；之前（或失败时）赛程页说还没出。
        bracket = try? await tournamentService.bracket(tournamentId)
        bracketLoaded = true
    }

    /** 底部栏回复组队邀请。 */
    func answer(accept: Bool) async {
        guard let entry = myEntry else { return }
        await act { try await self.tournamentService.answer(entryId: entry.id, accept: accept) }
    }

    /** 队长给待付款的报名付款：重新取付款意图，弹付款面板。 */
    func payMine() async {
        guard let entry = myEntry else { return }
        await act {
            let change = try await self.tournamentService.pay(entryId: entry.id)
            guard let secret = change.clientSecret, let account = change.providerAccountId, let key = change.publishableKey else { return }
            await self.present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret))
        }
    }

    /** 底部「立即报名」：只有一个组别开着就直接打开报名面板，否则切到组别页去选。 */
    func registerNow() {
        let open = openDivisions
        if open.count == 1, let only = open.first {
            openRegister(only)
        } else {
            tab = .divisions
        }
    }

    private func act(_ block: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "tournament_action_failed")
        }
    }

    private func present(_ intent: ConnectedPaymentIntent) async {
        switch await ConnectedPaymentSheet.present(intent) {
        case .completed:
            outcome = .registered
            tournamentService.invalidate()
        case .canceled: break
        case .failed: outcome = .awaitingPayment
        }
    }

    func openRegister(_ division: TournamentDivision) {
        outcome = nil
        sheet = TournamentRegisterState(division: division, method: methods.first)
        guard division.format != .singles else { return }
        let session = sessionStore.state.value
        let key = FriendsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, limit: Self.friendsPage)
        Task {
            do {
                let friends = try await socialService.getFriends(key)
                sheet?.friends = Loadable(data: friends, isLoading: false)
            } catch {
                sheet?.friends = Loadable(isLoading: false, error: UiError(error))
            }
        }
    }

    func toggleTeammate(_ profileId: String) {
        guard var current = sheet else { return }
        if current.teammates.contains(profileId) {
            current.teammates.removeAll { $0 == profileId }
        } else if current.teammates.count < current.maxTeammates {
            current.teammates.append(profileId)
        }
        sheet = current
    }

    func register() async {
        guard let current = sheet, current.ready else { return }
        let method = current.method ?? .offline
        let name = current.name.trimmingCharacters(in: .whitespaces)
        sheet?.submitting = true
        sheet?.error = nil
        do {
            let change = try await tournamentService.register(
                divisionId: current.division.id, name: current.solo || name.isEmpty ? nil : name, teammates: current.teammates, method: method
            )
            sheet = nil
            if let secret = change.clientSecret, let account = change.providerAccountId, let key = change.publishableKey {
                await present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret))
            } else {
                outcome = change.status
            }
        } catch {
            sheet?.submitting = false
            sheet?.error = UiError(error).text(fallback: String(localized: "tournament_action_failed"))
        }
    }

    func dismissOutcome() {
        outcome = nil
    }
}
