import Foundation
import Testing
@testable import PulsoLinkCore

struct WireCodingTests {
    @Test func decodesSnakeCaseAndFillsDefaults() throws {
        let item = try decodeWire(ProfileItem.self, #"{"profile_id":"p1","kind":"organization","display_name":"Ann"}"#)
        #expect(item.profileId == "p1")
        #expect(item.kind == .organization)
        #expect(item.roles.isEmpty)
        #expect(item.displayName == "Ann")
        #expect(item.avatarImageId == nil)
    }

    @Test func unknownEnumFallsBack() throws {
        let item = try decodeWire(ProfileItem.self, #"{"profile_id":"p1","kind":"galaxy"}"#)
        #expect(item.kind == .community)
    }

    @Test func encodesSnakeCaseKeysAndWireValues() throws {
        let body = LoginWithGoogleRequest(
            idToken: "t", deviceId: "d", signupPlatform: .pulsoloop, lang: .zhHant, clientOs: .ios
        )
        let json = try #require(String(data: WireCoding.encoder.encode(body), encoding: .utf8))
        #expect(json.contains(#""id_token":"t""#))
        #expect(json.contains(#""signup_platform":"pulsoloop""#))
        #expect(json.contains(#""lang":"zh-Hant""#))
        #expect(json.contains(#""client_os":"ios""#))
    }

    @Test func nilFieldsAreNotWritten() throws {
        let json = try #require(String(data: WireCoding.encoder.encode(SendEmailVerificationCodeRequest()), encoding: .utf8))
        #expect(json == "{}")
    }

    @Test func listEnvelopeDefaults() throws {
        let page = try decodeWire(DataResponse<ListWithTotal<ProfileItem>>.self, #"{"data":{}}"#)
        let list = try page.dataOrThrow("test")
        #expect(list.items.isEmpty)
        #expect(list.total == 0)
    }

    @Test func missingDataThrows() throws {
        let empty = try decodeWire(DataResponse<TokensResponse>.self, "{}")
        #expect(throws: MissingDataError.self) { try empty.dataOrThrow("RefreshTokens") }
    }

    @Test func themeSettingsDefaultsMatchWeb() throws {
        let settings = try decodeWire(PulsoThemeSettings.self, #"{"accent":"jade","scaling":"110%"}"#)
        #expect(settings.accent == .jade)
        #expect(settings.scaling.factor == 1.1)
        #expect(settings.appearance == .system)
        #expect(settings.gray == .slate)
        #expect(settings.panelBackground == .translucent)
    }
}
