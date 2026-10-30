import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 待处理的好友请求（Android `FriendRequestsViewModel`），离线优先；接受 / 拒绝 / 撤回会先在本地删掉这一行。 */
@MainActor
@Observable
final class FriendRequestsModel {
    private(set) var requests = Loadable<[FriendRequestItem]>()
    var direction = SocialFriendRequestDirection.incoming
    private(set) var actingId: String?

    @ObservationIgnored @Injected(\.socialService) private var socialService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let key: FriendRequestsKey

    init() {
        let session = Container.shared.authSessionStore().state.value
        key = FriendRequestsKey(accountId: session.currentAccountId, profileId: session.currentProfileId, status: .pending)
    }

    var visible: [FriendRequestItem] { (requests.data ?? []).filter { $0.direction == direction } }

    func displayName(_ item: FriendRequestItem) -> String {
        item.profile.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? String(item.counterpartyProfileId.prefix(8))
    }

    func avatarURL(_ item: FriendRequestItem) -> URL? {
        ImageURLs.image(item.profile.avatarImageId, base: config.apiBaseURL)
    }

    func observe() async {
        for await response in socialService.streamFriendRequests(key) {
            requests = requests.reduce(response)
        }
    }

    func refresh() {
        socialService.refreshFriendRequests()
    }

    func accept(_ id: String) async { await act(id) { try await self.socialService.acceptFriendRequest(id) } }
    func reject(_ id: String) async { await act(id) { try await self.socialService.rejectFriendRequest(id) } }
    func cancel(_ id: String) async { await act(id) { try await self.socialService.cancelFriendRequest(id) } }

    private func act(_ id: String, _ block: @escaping () async throws -> Void) async {
        actingId = id
        defer { actingId = nil }
        do {
            try await block()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "shell_social_request_action_failed")
        }
    }
}

/** 好友请求（Android `FriendRequestsScreen`）：收到的 / 发出的，收到的可接受或拒绝，发出的可撤回。 */
struct FriendRequestsView: View {
    @State private var model = FriendRequestsModel()

    var body: some View {
        List {
            Section {
                Picker(selection: $model.direction) {
                    Text("shell_social_requests_incoming").tag(SocialFriendRequestDirection.incoming)
                    Text("shell_social_requests_outgoing").tag(SocialFriendRequestDirection.outgoing)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if let error = model.requests.error, model.requests.data != nil {
                PulsoErrorBanner(error) { model.refresh() }
            }
            if model.requests.data == nil {
                if let error = model.requests.error {
                    PulsoLoadErrorView(error) { model.refresh() }.listRowBackground(Color.clear)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200).listRowBackground(Color.clear)
                }
            } else if model.visible.isEmpty {
                ContentUnavailableView("shell_social_requests_empty", systemImage: "person.2", description: Text("shell_social_requests_empty_hint"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(model.visible, id: \.friendRequestId) { item in row(item) }
            }
        }
        .navigationTitle("shell_social_requests")
        .refreshable { model.refresh() }
        .task { await model.observe() }
    }

    private func row(_ item: FriendRequestItem) -> some View {
        let acting = model.actingId == item.friendRequestId
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                PulsoAvatar(url: model.avatarURL(item), size: 40, fallbackText: model.displayName(item))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.displayName(item)).font(.subheadline.weight(.semibold))
                    if let message = item.message, !message.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(verbatim: message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                switch item.direction {
                case .incoming:
                    Button("shell_social_accept") { Task { await model.accept(item.friendRequestId) } }.buttonStyle(.glassProminent)
                    Button("shell_social_reject") { Task { await model.reject(item.friendRequestId) } }.buttonStyle(.glass)
                case .outgoing:
                    Button("shell_social_cancel_request") { Task { await model.cancel(item.friendRequestId) } }.buttonStyle(.glass)
                }
                if acting { ProgressView() }
            }
            .disabled(acting)
        }
    }
}
