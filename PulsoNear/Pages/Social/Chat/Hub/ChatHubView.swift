import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 消息（Android `ChatHubScreen`）：私聊 / 群聊两个标签；右上角铃铛进通知（有未读时带红点），「+」进社交。 */
struct ChatHubView: View {
    @State private var rows = ConversationRows()
    @State private var tab = ChatTab.direct
    @State private var hasNotificationUnread = false
    @Injected(\.inboxIndicatorStore) private var inbox

    var body: some View {
        let current = tab == .direct ? rows.direct : rows.group
        List {
            Section {
                Picker(selection: $tab) {
                    Text("shell_chat_tab_direct").tag(ChatTab.direct)
                    Text("shell_chat_tab_group").tag(ChatTab.group)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if let list = current.data {
                if let error = current.error {
                    PulsoErrorBanner(error) { rows.refresh() }
                }
                if list.isEmpty {
                    ContentUnavailableView {
                        Text("shell_chat_empty")
                    } description: {
                        Text("shell_chat_empty_hint")
                    } actions: {
                        NavigationLink("shell_chat_open_social", value: NearRoute.social(tab: .friends)).buttonStyle(.glassProminent)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(list) { row in
                    NavigationLink(value: NearRoute.conversation(conversationId: row.conversationId, isGroup: row.isGroup)) {
                        ConversationRowView(row: row)
                    }
                }
            } else if let error = current.error {
                PulsoLoadErrorView(error) { rows.refresh() }.listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
            }
        }
        .navigationTitle("shell_dest_chat_hub")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: NearRoute.notifications) {
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            if hasNotificationUnread { Circle().fill(.red).frame(width: 8, height: 8).offset(x: 3, y: -3) }
                        }
                }
                .accessibilityLabel(Text("shell_dest_notifications"))
                NavigationLink(value: NearRoute.social(tab: .friends)) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("shell_chat_open_social"))
            }
        }
        .refreshable { rows.refresh() }
        .task { await rows.observe() }
        .task {
            for await state in inbox.state.values() {
                hasNotificationUnread = state.hasNotificationUnread
            }
        }
    }
}
