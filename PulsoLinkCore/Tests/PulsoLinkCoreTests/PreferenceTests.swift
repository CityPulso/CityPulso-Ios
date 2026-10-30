import Foundation
import Testing
@testable import PulsoLinkCore

private let loopPages = Set(ShellDestination.allCases)

struct ResolvedNavPreferenceTests {
    @Test func duplicateAndUnavailablePagesFallBackWithTheirOwnIcons() {
        var wire = AndroidPreference()
        wire.slot1 = AndroidNavSlot(destination: .forum, icon: .chat)
        wire.slot4 = AndroidNavSlot(destination: .forum, icon: .chat)
        wire.slot6 = AndroidNavSlot(destination: .wallet, icon: .wallet)

        let organization = ResolvedAndroidPreference.resolve(wire, kind: .organization, supported: loopPages)

        // forum 占了槽 1，槽 4 回落非社区默认（聊天）；钱包只属于社区档，槽 6 回落设置
        #expect(organization.slot1 == ResolvedAndroidNavSlot(.forum, iconPack: .chat))
        #expect(organization.slot4 == ResolvedAndroidNavSlot(.chatHub))
        #expect(organization.slot6 == ResolvedAndroidNavSlot(.settings))
        #expect(Set(organization.capsuleSlots.map(\.destination) + [organization.slot6.destination]).count == 5)
    }

    @Test func pagesThisAppLacksAreReplaced() {
        var wire = AndroidPreference()
        wire.slot2 = AndroidNavSlot(destination: .courses)
        let near = Set(ShellDestination.allCases).subtracting([.courses, .coaching, .tournaments])

        #expect(ResolvedAndroidPreference.resolve(wire, kind: .community, supported: near).slot2 == ResolvedAndroidNavSlot(.venueSearch, iconPack: .place))
    }

    @Test func appsTrayListsEveryOtherAvailablePage() {
        let tray = ResolvedAndroidPreference.default.appsTrayDestinations(kind: .community, supported: loopPages)
        #expect(!tray.contains(.explore))
        #expect(!tray.contains(.create))
        #expect(tray.contains(.wallet))
        #expect(tray.count == ShellDestination.allCases.count - 5)
    }

    @Test func eventPreferenceIsClamped() {
        var event = EventPreference()
        event.nearbyPageSize = 500
        event.nearbyRadiusMaxM = 100
        event.nearbyRadiusMinM = 0
        let resolved = ResolvedEventPreference(event)
        #expect(resolved.nearbyPageSize == 40)
        #expect(resolved.nearbyRadiusMaxM == 500)
        #expect(resolved.nearbyRadiusMinM == 10)
    }
}

struct PreferenceWireTests {
    @Test func navSlotsDecodeLeniently() throws {
        let android = try decodeWire(AndroidPreference.self, #"""
        {"slot1":"EXPLORE","slot2":{"destination":"forum","icon":"nope"},"slot3":{"destination":"gone"},
         "slot4":{"destination":"wallet","icon":"WALLET"},"loopLauncherIcon":"dark"}
        """#)
        #expect(android.slot1 == AndroidNavSlot())
        #expect(android.slot2 == AndroidNavSlot(destination: .forum, icon: .forum))
        #expect(android.slot3 == AndroidNavSlot())
        #expect(android.slot4 == AndroidNavSlot(destination: .wallet, icon: .wallet))
        #expect(android.loopLauncherIcon == .dark)
    }

    @Test func camelCaseAndSnakeCaseKeysBothDecode() throws {
        let camel = try decodeWire(Preference.self, #"{"map":{"mapLightStyle":"bright","showEventCards":true}}"#)
        let snake = try decodeWire(Preference.self, #"{"map":{"map_light_style":"bright","show_event_cards":true}}"#)
        #expect(camel == snake)
        #expect(camel.map?.mapLightStyle == .bright)
    }

    @Test func uploadIsCamelCaseWithoutNullsOrDefaults() throws {
        var local = ResolvedPreference()
        local.theme.accent = .blue
        let json = String(decoding: try JSONEncoder().encode(local.serverPreference), as: UTF8.self)
        #expect(json.contains(#""accent":"blue""#))
        #expect(json.contains(#""mapLightStyle":"positron""#))
        #expect(json.contains(#""destination":"EXPLORE""#))
        #expect(!json.contains("null"))
        #expect(!json.contains("nearbyPageSize"))
    }

    @Test func serverPreferenceRoundTrips() throws {
        var local = ResolvedPreference()
        local.theme.accent = .jade
        local.android.slot2 = ResolvedAndroidNavSlot(.wallet)
        local.event.hiddenLoopModules = [.tableTennis]
        let parsed = ResolvedPreference(server: local.serverPreference, kind: .community, supported: loopPages)
        #expect(parsed == local)
    }
}

struct PreferenceBootstrapTests {
    private func setup() -> (PreferenceBootstrap, PreferenceRepository) {
        let repository = PreferenceRepository(defaults: freshDefaults())
        let bootstrap = PreferenceBootstrap(
            profileStore: ProfileStore(),
            preferenceRepository: repository,
            config: stubConfig(host: "unused", shellDestinations: loopPages)
        )
        return (bootstrap, repository)
    }

    private func account(_ preference: String?) throws -> CurrentFullAccountInformation {
        let response = try decodeWire(
            DataResponse<FullAccountInformationWithCommunityProfile>.self,
            communityAccountJSON(preference: preference)
        )
        return .community(try response.dataOrThrow("Test"))
    }

    @Test func serverPreferenceReplacesLocalButKeepsLocalOnlyFields() throws {
        let (bootstrap, repository) = setup()
        repository.update {
            $0.map.mapRich = false
            $0.android.loopLauncherIcon = .dark
        }

        let changed = bootstrap.applyFromProfile(try account(#"{"theme":{"accent":"blue"},"android":{"slot1":{"destination":"FORUM"}}}"#))

        let applied = repository.preference.value
        #expect(changed)
        #expect(applied.theme.accent == .blue)
        #expect(applied.map.mapRich == false)
        #expect(applied.android.slot1 == ResolvedAndroidNavSlot(.forum))
        // 服务端没写桌面图标：保留本地
        #expect(applied.android.loopLauncherIcon == .dark)
    }

    @Test func missingServerPreferenceKeepsLocal() throws {
        let (bootstrap, repository) = setup()
        repository.update { $0.theme.accent = .grass }
        #expect(!bootstrap.applyFromProfile(try account(nil)))
        #expect(repository.preference.value.theme.accent == .grass)
    }

    @Test func samePreferenceIsAppliedOnce() throws {
        let (bootstrap, repository) = setup()
        let info = try account(#"{"theme":{"accent":"blue"}}"#)
        bootstrap.applyFromProfile(info)
        repository.update { $0.theme.accent = .ruby }
        #expect(!bootstrap.applyFromProfile(info))
        #expect(repository.preference.value.theme.accent == .ruby)
    }

    @Test func storedPreferenceSurvivesRestart() {
        let defaults = freshDefaults()
        PreferenceRepository(defaults: defaults).update { $0.android.slot3 = ResolvedAndroidNavSlot(.wallet) }
        #expect(PreferenceRepository(defaults: defaults).preference.value.android.slot3 == ResolvedAndroidNavSlot(.wallet))
    }
}
