import Factory

extension Container {
    /** 每种活动的 Service，按 [NearActivityKind] 取（跨活动类型的页面用）。 */
    var nearActivityServices: Factory<[NearActivityKind: any NearActivityService]> {
        self {
            let services: [any NearActivityService] = [
                self.mahjongService(), self.texasHoldemService(), self.boardGameService(), self.werewolfService(),
                self.scriptMurderService(), self.billiardsService(), self.escapeRoomService(), self.esportsService(),
                self.ktvService(), self.barPartyService(), self.indoorSocialService(), self.outdoorSocialService(),
                self.languageExchangeService(), self.bookClubService(), self.diyService(),
            ]
            return Dictionary(uniqueKeysWithValues: services.map { ($0.activityType, $0) })
        }.singleton
    }
}
