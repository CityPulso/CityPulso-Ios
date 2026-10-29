import NukeUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

extension LoopSport {
    /**
     * 运动的 Radix 色阶（对应 Android `colorScale()` / `ExploreSportColors`），和 WEB 针的颜色一致，
     * 胶囊、针、标签三端一样。
     */
    var colorScale: RadixScale {
        switch self {
        case .badminton: .jade
        case .tennis: .gold
        case .pickleball: .crimson
        case .basketball: .orange
        case .football: .indigo
        case .baseball: .tomato
        case .golf: .grass
        case .hiking: .brown
        case .fishing: .teal
        case .ski: .blue
        case .tableTennis: .violet
        }
    }
}

/** 活动或球馆封面：有图显示图，没有就在容器色上显示运动图标，不留空框（Android `SportCover`）。调用方定大小和裁切。 */
struct SportCover: View {
    let url: URL?
    let sport: LoopSport
    var iconSize: CGFloat = 40

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if let url {
                PulsoRemoteImage(url: url)
            } else {
                Image(sport.iconAsset).resizable().scaledToFit().frame(width: iconSize, height: iconSize)
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
