import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 第 0 步（Android `ActivityTypePickStep`）：一句标题，然后按三组（牌桌与推理 / 场馆娱乐 / 交友与兴趣，WEB
 * `NEAR_ACTIVITY_TYPE_GROUPS`）列出活动类型，一行两张卡，用类型的颜色、图标、建议人数和提示标签。
 */
struct CreateActivityTypePickView: View {
    let onSelect: (NearActivityKind) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("create_flow_hero_title").font(.title2.bold())
                    Text("create_flow_hero_body").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                ForEach(NearActivityGroup.allCases, id: \.self) { group in
                    Text(group.labelKey).font(.headline).padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(NearActivityKind.allCases.filter { $0.group == group }) { kind in
                            ActivityTypePickCard(kind: kind) { onSelect(kind) }
                        }
                    }
                }
                Text("create_flow_intro_hint").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
            }
            .padding()
        }
    }
}

/** 一种活动：类型色的渐变卡；还没开放的变淡、不能选。 */
private struct ActivityTypePickCard: View {
    let kind: NearActivityKind
    let onTap: () -> Void

    var body: some View {
        let scale = kind.colorScale
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(kind.iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .frame(width: 56, height: 56)
                        .background(scale.step(5), in: .circle)
                    Spacer(minLength: 8)
                    // 标签在右上角、和图标同一行，有没有标签卡片都一样高。
                    VStack(alignment: .trailing, spacing: 4) {
                        if !kind.available { tag(Text("create_flow_coming_soon"), scale: scale) }
                        if let notice = kind.notice { tag(Text(notice.tagKey), scale: notice.scale) }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.labelKey).font(.headline).lineLimit(1)
                    // 类型的默认人数只是建议，发起人在表单里可以改。
                    Text(verbatim: kind.defaultMinParticipants == kind.defaultMaxParticipants
                        ? localizedFormat("create_flow_suggested_participants_exact", kind.defaultMaxParticipants)
                        : localizedFormat("create_flow_suggested_participants_range", kind.defaultMinParticipants, kind.defaultMaxParticipants))
                        .font(.caption)
                        .foregroundStyle(scale.step(11))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [scale.step(3), scale.step(4)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 16))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(!kind.available)
        .opacity(kind.available ? 1 : 0.7)
    }

    private func tag(_ text: Text, scale: RadixScale) -> some View {
        text
            .font(.caption2)
            .foregroundStyle(scale.step(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(scale.step(3), in: .capsule)
    }
}

extension NearActivityNotice {
    /** 类型卡上的短标签。 */
    var tagKey: LocalizedStringKey {
        switch self {
        case .noGambling: "create_activity_tag_no_gambling"
        case .adultsOnly: "create_activity_tag_adults_only"
        }
    }
}
