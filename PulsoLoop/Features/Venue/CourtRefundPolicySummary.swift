import PulsoLinkUI
import SwiftUI

/** 入口的退款政策摘要（Android `<Sport>RefundPolicySummary`）：类型、分档（时间越早退越多）、备注和两条固定说明。 */
struct CourtRefundPolicySummary: View {
    let policy: CourtRefundPolicy
    let tiers: [CourtRefundTierUi]
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

/** 分钟 → 「1.5 小时」（本地化单位，最多一位小数；Android `formatBundleHours`）。 */
func formatBundleHours(_ minutes: Int, locale: Locale = .current) -> String {
    let formatter = MeasurementFormatter()
    formatter.locale = locale
    formatter.unitStyle = .short
    formatter.unitOptions = .providedUnit
    formatter.numberFormatter.maximumFractionDigits = 1
    return formatter.string(from: Measurement(value: Double(minutes) / 60, unit: UnitDuration.hours))
}

/** 分钟 → 只有数字的小时数（「1.5」），大数字旁边已经写了单位。 */
func formatBundleHourCount(_ minutes: Int, locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: Double(minutes) / 60)) ?? ""
}
