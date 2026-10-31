import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 消息（Android `ChatHubScreen`）：一级「私聊 | 群聊」标签，下面通栏的会话行（没有箭头和分隔线）；
 * 置顶的排在最前、铺一条灰底，可以收成一行。右上角铃铛进通知（有未读时带红点），「+」进社交。
 */
struct ChatHubView: View {
    @State private var rows = ConversationRows()
    @State private var tab = ChatTab.direct
    @State private var hasNotificationUnread = false
    /** 置顶的聊天收成一行「N 个置顶聊天」。 */
    @State private var pinnedCollapsed = false
    @Injected(\.inboxIndicatorStore) private var inbox
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        let current = tab == .direct ? rows.direct : rows.group
        VStack(spacing: 0) {
            PulsoUnderlineTabRow([ChatTab.direct, .group], selection: $tab) { tab in
                Text(tab == .direct ? "shell_chat_tab_direct" : "shell_chat_tab_group")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let list = current.data {
                        if let error = current.error {
                            PulsoErrorBanner(error) { rows.refresh() }.padding(PulsoSpace.s4)
                        }
                        if list.isEmpty {
                            PulsoEmptyState(Text("shell_chat_empty"), description: Text("shell_chat_empty_hint"), style: .campfire) {
                                NavigationLink("shell_chat_open_social", value: NearRoute.social(tab: .friends)).buttonStyle(.pulso())
                            }
                            .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
                        }
                        let pinned = list.filter { $0.pinnedAt != nil }
                        if !pinned.isEmpty {
                            VStack(spacing: 0) {
                                if pinnedCollapsed {
                                    Button { withAnimation { pinnedCollapsed = false } } label: {
                                        PinnedFoldedRow(pinned: pinned).padding(.horizontal, PulsoSpace.s4).padding(.vertical, PulsoSpace.s3)
                                    }
                                    .buttonStyle(.pulsoRow)
                                } else {
                                    ForEach(pinned) { row in conversationLink(row) }
                                    Button { withAnimation { pinnedCollapsed = true } } label: {
                                        Label("shell_chat_pinned_collapse", systemImage: "chevron.up")
                                            .font(.footnote)
                                            .foregroundStyle(palette.secondaryText)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, PulsoSpace.s2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(palette.gray.step(3))
                        }
                        ForEach(list.filter { $0.pinnedAt == nil }) { row in conversationLink(row) }
                    } else if let error = current.error {
                        PulsoLoadErrorView(error) { rows.refresh() }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
            }
            .refreshable { rows.refresh() }
        }
        .navigationTitle("shell_dest_chat_hub")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: NearRoute.notifications) {
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            if hasNotificationUnread { Circle().fill(palette.error).frame(width: 8, height: 8).offset(x: 3, y: -3) }
                        }
                }
                .accessibilityLabel(Text("shell_dest_notifications"))
                NavigationLink(value: NearRoute.social(tab: .friends)) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("shell_chat_open_social"))
            }
        }
        .task { await rows.observe() }
        .task {
            for await state in inbox.state.values() {
                hasNotificationUnread = state.hasNotificationUnread
            }
        }
    }

    /** 一行会话：左右 16、上下 12，整行可点。 */
    private func conversationLink(_ row: ConversationRowUi) -> some View {
        NavigationLink(value: NearRoute.conversation(conversationId: row.conversationId, isGroup: row.isGroup)) {
            ConversationRowView(row: row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PulsoSpace.s4)
                .padding(.vertical, PulsoSpace.s3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pulsoRow)
    }
}

/** 收起的置顶聊天：头像叠在一起和「N 个置顶聊天」，点开展开。 */
private struct PinnedFoldedRow: View {
    let pinned: [ConversationRowUi]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(pinned.prefix(3)) { row in
                    PulsoAvatar(url: row.avatarURL, size: 32, fallbackText: row.title)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }
            Text(verbatim: localizedFormat("shell_chat_pinned_folded", pinned.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down").foregroundStyle(.secondary)
        }
    }
}
