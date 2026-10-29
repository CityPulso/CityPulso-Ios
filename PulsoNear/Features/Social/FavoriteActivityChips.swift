import PulsoLinkCore
import SwiftUI

extension FavoriteActivity {
    /** 喜欢的活动背后的 Near 活动类型（图标 + 名称），wire 值相同。 */
    var kind: NearActivityKind { NearActivityKind.fromWire(rawValue) }

    /** 按 App 里活动类型的顺序（Android 编辑页的排列）。 */
    static var ordered: [FavoriteActivity] {
        NearActivityKind.allCases.map { FavoriteActivity.fromWire($0.rawValue) }
    }
}

/** 资料里喜欢的活动：图标 + 名称的胶囊；没选时不画（对应 Android `FavoriteActivityChips`）。 */
struct FavoriteActivityChips: View {
    let activities: [FavoriteActivity]

    var body: some View {
        if !activities.isEmpty {
            HStack(spacing: 8) {
                ForEach(activities, id: \.self) { activity in
                    HStack(spacing: 4) {
                        Image(activity.kind.iconAsset).resizable().frame(width: 16, height: 16)
                        Text(activity.kind.labelKey).font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.fill.tertiary, in: .capsule)
                }
            }
        }
    }
}
