import PulsoLinkCore

/** 任何球馆写操作后让全部球馆查询重拉（Android `VenueEventBus`、WEB `events/venue.ts`）。 */
enum VenueEvent: Sendable {
    case invalidate
}

typealias VenueEventBus = EventBroadcast<VenueEvent>

extension EventBroadcast where Event == VenueEvent {
    func invalidate() {
        emit(.invalidate)
    }
}
