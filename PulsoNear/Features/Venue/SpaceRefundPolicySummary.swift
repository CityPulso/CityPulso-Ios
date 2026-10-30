import PulsoLinkUI
import SwiftUI

/** 入口的退款政策摘要（Android `<ActivityType>RefundPolicySummary`）：类型、分档（时间越早退越多）、备注和两条固定说明。 */
struct SpaceRefundPolicySummary: View {
    let policy: SpaceRefundPolicy
    let tiers: [SpaceRefundTierUi]
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(policy.summaryKey).font(.subheadline)
            if policy == .tiered {
                ForEach(tiers.sorted { $0.hoursBeforeStart > $1.hoursBeforeStart }, id: \.self) { tier in
                    Label {
                        Text(verbatim: localizedFormat("venue_refund_summary_tier", String(tier.hoursBeforeStart), String(tier.refundPercent)))
                    } icon: {
                        Text(verbatim: "•").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                Label { Text("venue_refund_summary_tier_later") } icon: { Text(verbatim: "•").foregroundStyle(.secondary) }
                    .font(.footnote)
            }
            if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: note).font(.footnote).foregroundStyle(.secondary)
            }
            Text("venue_refund_summary_venue_cancels").font(.footnote).foregroundStyle(.secondary)
            Text("venue_refund_summary_online_only").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
