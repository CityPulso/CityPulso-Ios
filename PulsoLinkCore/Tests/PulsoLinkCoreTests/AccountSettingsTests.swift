import Foundation
import Testing
@testable import PulsoLinkCore

struct PrivacySettingsTests {
    @Test func decodesAndRoundTripsIntoTheUpdateRequest() throws {
        let settings = try decodeWire(PrivacySettings.self, #"""
        {"profile_id":"p1","profile_scope":"community","friend_request_policy":"mutual_follows",
         "direct_message_policy":["friends","people_following_me","unknown"],
         "show_friend_list":true,"show_block_list":false,"show_following_list":true,"show_follower_list":false,
         "updated_at":"2026-10-29T00:00:00Z"}
        """#)
        #expect(settings.friendRequestPolicy == .mutualFollows)
        #expect(settings.directMessagePolicy == [.friends, .peopleFollowingMe, .friends])
        #expect(settings.groupInvitePolicy.isEmpty)

        let body = String(decoding: try WireCoding.encoder.encode(UpdatePrivacySettingsRequest(settings)), as: UTF8.self)
        #expect(body.contains(#""friend_request_policy":"mutual_follows""#))
        #expect(body.contains(#""group_invite_policy":[]"#))
    }
}

struct EmailInvalidationTests {
    @Test func firesOnceUpFrontThenOnEveryChangeOfThisAccount() async throws {
        let store = AuthSessionStore(persistence: AuthSessionPersistence(vault: MemoryVault()))
        store.state.set(completeSession())
        let events = AuthEventBus()
        let client = APIClient(config: stubConfig(host: "unused.stub"))
        let service = AuthService(
            auth: AuthRepository(publicAPI: AuthPublicAPI(client: client), protectedAPI: AuthProtectedAPI(client: client)),
            authEventBus: events,
            sessionStore: store
        )
        var iterator = service.emailInvalidations().makeAsyncIterator()
        #expect(await iterator.next() != nil)

        // 订阅在 Task 里建立，给它一拍再发事件。
        try await Task.sleep(for: .milliseconds(20))
        events.emit(.invalidateEmails(accountId: "someone-else"))
        events.emit(.invalidateEmails(accountId: "acc-1"))
        #expect(await iterator.next() != nil)
    }
}
