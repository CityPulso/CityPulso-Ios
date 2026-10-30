import NukeUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

extension NearActivityKind {
    /** 活动类型的 Radix 色阶（Android `colorScale()`，WEB `NEAR_ACTIVITY_TYPE_PIN_COLOR`）：针、胶囊、卡片三端一样。 */
    var colorScale: RadixScale {
        switch self {
        case .mahjong: .jade
        case .texasHoldem: .crimson
        case .boardGame: .gold
        case .werewolf: .purple
        case .scriptMurder: .tomato
        case .billiards: .grass
        case .escapeRoom: .indigo
        case .esports: .cyan
        case .ktv: .pink
        case .barParty: .orange
        case .indoorSocial: .plum
        case .outdoorSocial: .green
        case .languageExchange: .blue
        case .bookClub: .brown
        case .diy: .ruby
        }
    }
}

/** 活动或门店封面：有图显示图，没有就在容器色上显示活动类型图标，不留空框（Android `ActivityTypeCover`）。调用方定大小和裁切。 */
struct ActivityTypeCover: View {
    let url: URL?
    let activityType: NearActivityKind
    var iconSize: CGFloat = 40

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if let url {
                PulsoRemoteImage(url: url)
            } else {
                Image(activityType.iconAsset).resizable().scaledToFit().frame(width: iconSize, height: iconSize)
            }
        }
    }
}

/** 「850 米」/「1.3 公里」（Android `distanceLabel`）。 */
func distanceLabel(_ meters: Double) -> String {
    meters < 1000
        ? localizedFormat("map_venue_pin_distance_m", String(Int(meters.rounded())))
        : localizedFormat("map_venue_pin_distance_km", String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), meters / 1000))
}
