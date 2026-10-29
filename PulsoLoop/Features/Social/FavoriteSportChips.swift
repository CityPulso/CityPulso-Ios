import PulsoLinkCore
import SwiftUI

extension FavoriteSport {
    /** 喜欢的运动背后的 Loop 运动（图标 + 名称），wire 值相同。 */
    var loopSport: LoopSport { LoopSport.fromWire(rawValue) }
}

/** 资料里喜欢的运动：运动图标 + 名称的胶囊；没选时不画（对应 Android `FavoriteSportChips`）。 */
struct FavoriteSportChips: View {
    let sports: [FavoriteSport]

    var body: some View {
        if !sports.isEmpty {
            HStack(spacing: 8) {
                ForEach(sports, id: \.self) { sport in
                    HStack(spacing: 4) {
                        Image(sport.loopSport.iconAsset).resizable().frame(width: 16, height: 16)
                        Text(sport.loopSport.labelKey).font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }
}
