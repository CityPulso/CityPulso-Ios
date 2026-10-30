import SwiftUI

/** 带底色的小标签（Android `VenueChip`）：状态、能否收款这类一两个字的标记。 */
struct VenueChip: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tone.opacity(0.14), in: .capsule)
    }
}
