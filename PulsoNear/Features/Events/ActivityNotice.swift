import PulsoLinkUI
import SwiftUI

/** 这种活动的提示，做成有底色的提示框；发起、详情和报名显示同一个（Android `ActivityNoticeCallout`，WEB `notice.*`）。 */
struct ActivityNoticeCallout: View {
    let notice: NearActivityNotice

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice == .noGambling ? "exclamationmark.triangle" : "info.circle")
            Text(notice.bodyKey).font(.footnote)
        }
        .foregroundStyle(notice.scale.step(11))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notice.scale.step(3), in: .rect(cornerRadius: 16))
    }
}

extension NearActivityNotice {
    var bodyKey: LocalizedStringKey {
        switch self {
        case .noGambling: "activity_notice_gambling"
        case .adultsOnly: "activity_notice_adults_only"
        }
    }

    /** 禁赌是红色警告，仅限成人是琥珀色提醒（Android `colorScale`）。 */
    var scale: RadixScale {
        switch self {
        case .noGambling: .red
        case .adultsOnly: .amber
        }
    }
}
