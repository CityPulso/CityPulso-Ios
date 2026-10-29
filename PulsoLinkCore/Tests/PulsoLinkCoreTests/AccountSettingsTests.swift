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

private let emailHost = "emails.stub"

@Suite(.serialized)
struct EmailQueryTests {
    @Test func refetchesOnEmailInvalidationAndLogout() async throws {
        StubProtocol.reset(emailHost)
        StubProtocol.serve(emailHost) { _ in
            let count = StubProtocol.received(emailHost).count
            return (200, #"{"data":{"items":[{"id":"e\#(count)","account_id":"acc-1","email":"a@b.c","is_primary":true,"created_at":"","updated_at":""}],"total":1}}"#)
        }
        let events = AuthEventBus()
        let client = APIClient(config: stubConfig(host: emailHost), interceptor: nil, configuration: StubProtocol.configuration)
        let store = AuthQueryStore(
            auth: AuthRepository(publicAPI: AuthPublicAPI(client: client), protectedAPI: AuthProtectedAPI(client: client)),
            authEventBus: events
        )
        var iterator = store.emails.stream("acc-1").makeAsyncIterator()
        guard case .loading = await iterator.next() else { Issue.record("expected loading"); return }
        guard case let .data(first) = await iterator.next() else { Issue.record("expected data"); return }
        #expect(first.map(\.id) == ["e1"])

        try await Task.sleep(for: .milliseconds(20))
        events.emit(.updateAccountSuccess)
        events.emit(.invalidateEmails(accountId: "acc-1"))
        guard case .loading = await iterator.next() else { Issue.record("expected loading"); return }
        guard case let .data(second) = await iterator.next() else { Issue.record("expected data"); return }
        #expect(second.map(\.id) == ["e2"])
        #expect(StubProtocol.received(emailHost).count == 2)
    }
}
