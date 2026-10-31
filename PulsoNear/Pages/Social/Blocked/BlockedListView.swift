import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 黑名单（Android `BlockedListViewModel`）：我拉黑的人，最新的在前，每人一个解除拉黑。 */
@MainActor
@Observable
final class BlockedListModel {
    let rows: any PagedRows<BlockedItem>
    private(set) var busyId: String?

    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init() {
        rows = Container.shared.socialService().pageBlocked(Container.shared.authSessionStore().state.value.currentProfileId)
    }

    func displayName(_ item: BlockedItem) -> String {
        item.profile.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(item.blockedProfileId.prefix(8))
    }

    func avatarURL(_ item: BlockedItem) -> URL? {
        ImageURLs.image(item.profile.avatarImageId, base: config.apiBaseURL)
    }

    func unblock(_ item: BlockedItem) async {
        guard busyId == nil else { return }
        busyId = item.blockedProfileId
        defer { busyId = nil }
        do {
            try await socialService.unblock(item.blockedProfileId, item.blockedProfileScope)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_social_unblock_failed")
        }
    }
}

/** 黑名单（Android `BlockedListScreen`）：点人看主页，解除拉黑不用按住（规则里属于普通操作）。 */
struct BlockedListView: View {
    @State private var model = BlockedListModel()

    var body: some View {
        List {
            let rows = model.rows
            if !rows.items.isEmpty {
                ForEach(rows.items, id: \.blockedProfileId) { item in
                    HStack(spacing: PulsoSpace.s3) {
                        NavigationLink(value: NearRoute.socialProfile(profileId: item.blockedProfileId)) {
                            HStack(spacing: 12) {
                                PulsoAvatar(url: model.avatarURL(item), size: 40, fallbackText: model.displayName(item))
                                VStack(alignment: .leading) {
                                    Text(verbatim: model.displayName(item)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    if let username = item.profile.username {
                                        Text(verbatim: "@\(username)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        // 解除拉黑：灰色柔和小按钮（Android 黑名单行）；不用按住确认（hold-confirm 规则里属于普通点击）。
                        Button("shell_social_unblock") { Task { await model.unblock(item) } }
                            .buttonStyle(.pulso(.soft, tone: .gray, size: .small))
                            .disabled(model.busyId == item.blockedProfileId)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .onAppear { if item.blockedProfileId == rows.items.last?.blockedProfileId { rows.loadMore() } }
                }
            } else if rows.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
            } else if let error = rows.error {
                PulsoLoadErrorView(error) { Task { await rows.refresh() } }.listRowBackground(Color.clear)
            } else {
                PulsoEmptyState(Text("shell_social_blocked_empty")).frame(minHeight: 360).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle("shell_social_blocked_title")
        .refreshable { await model.rows.refresh() }
        .task { await model.rows.observe() }
    }
}
