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

/** 赛事详情（Android `TournamentDetailViewModel`）：赛事、对阵（有了才显示）、报名（平台付款走付款面板）。球馆有写操作就重拉。 */
@MainActor
@Observable
final class TournamentDetailModel {
    private static let friendsPage = 100

    let tournamentId: String
    private(set) var tournament = Loadable<TournamentDetail>()
    private(set) var bracket: TournamentBracket?
    var selectedDivisionId: String?
    var sheet: TournamentRegisterState?
    private(set) var outcome: TournamentEntryStatus?

    @ObservationIgnored @Injected(\.tournamentService) private var tournamentService
    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored @Injected(\.venueEventBus) private var eventBus
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

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

    func imageURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }

    func observe() async {
        await load()
        for await _ in eventBus.signals(where: { _ in true }) {
            await load()
        }
    }

    func load() async {
        tournament.isLoading = true
        do {
            tournament = try await Loadable(data: tournamentService.tournament(tournamentId), isLoading: false)
        } catch {
            tournament = Loadable(data: tournament.data, isLoading: false, error: UiError(error))
        }
        // 抽签以后才有对阵；之前（或失败时）这一段留空。
        if let value = try? await tournamentService.bracket(tournamentId) { bracket = value }
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
                switch await ConnectedPaymentSheet.present(ConnectedPaymentIntent(publishableKey: key, providerAccountId: account, clientSecret: secret)) {
                case .completed:
                    outcome = .registered
                    tournamentService.invalidate()
                case .canceled: break
                case .failed: outcome = .awaitingPayment
                }
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
