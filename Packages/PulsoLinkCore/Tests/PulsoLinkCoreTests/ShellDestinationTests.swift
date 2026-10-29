import Testing
@testable import PulsoLinkCore

struct ShellDestinationTests {
    @Test func communityOnlyPagesHiddenForOtherProfiles() {
        let supported: Set<ShellDestination> = [.explore, .calendar, .wallet, .settings]
        #expect(ShellDestination.available(for: .community, supported: supported) == [.explore, .calendar, .settings, .wallet])
        #expect(ShellDestination.available(for: .organization, supported: supported) == [.explore, .settings])
    }

    @Test func wireIsCaseInsensitive() {
        #expect(ShellDestination.fromWire(" venue_search ") == .venueSearch)
        #expect(ShellDestination.fromWire("") == nil)
        #expect(ShellDestination.fromWire("unknown") == nil)
    }
}
