import Factory

extension Container {
    /** 每种运动的 Service，按 [LoopSport] 取（跨运动页面用）。 */
    var loopSportServices: Factory<[LoopSport: any LoopSportService]> {
        self {
            let services: [any LoopSportService] = [
                self.badmintonService(), self.tennisService(), self.pickleballService(), self.basketballService(),
                self.footballService(), self.baseballService(), self.golfService(), self.hikingService(),
                self.fishingService(), self.skiService(), self.tableTennisService(),
            ]
            return Dictionary(uniqueKeysWithValues: services.map { ($0.sport, $0) })
        }.singleton
    }
}
