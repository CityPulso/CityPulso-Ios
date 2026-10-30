import Factory
import PulsoLinkCore

/** 桌台卡片上某些类型独有的标签（Android `KtvSpaceGrid` / `BilliardsSpaceGrid`）；通用的 [SpaceUi] 里没有这几项。 */
enum SpaceExtra: Hashable, Sendable {
    case ktvRoomSize(KtvRoomSize)
    case minSpend(Double)
    case billiardsTable(BilliardsTableType)
}

extension Container {
    /** 某门店某类型每张桌台的独有标签，按桌台 id；没有独有标签的类型返回 nil。 */
    @MainActor
    func spaceExtras(_ activityType: VenueActivityType, venueId: String) -> AsyncStream<QueryResponse<[String: [SpaceExtra]]>>? {
        let profileId = authSessionStore().state.value.currentProfileId
        let key = VenueKey(venueId: venueId, profileId: profileId)
        switch activityType {
        case .ktv:
            return ktvVenueQueryStore().spaces.stream(key).mapResponses { spaces in
                Dictionary(spaces.map { space in
                    (space.id, [.ktvRoomSize(space.roomSize)] + (space.minSpendAmount.map { [SpaceExtra.minSpend($0)] } ?? []))
                }, uniquingKeysWith: { first, _ in first })
            }
        case .billiards:
            return billiardsVenueQueryStore().spaces.stream(key).mapResponses { spaces in
                Dictionary(spaces.map { ($0.id, [SpaceExtra.billiardsTable($0.tableType)]) }, uniquingKeysWith: { first, _ in first })
            }
        default:
            return nil
        }
    }
}
