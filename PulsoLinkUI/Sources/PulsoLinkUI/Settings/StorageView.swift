import PulsoLinkCore
import SwiftUI

/** 设置 → 清除本地数据（Android `StorageViewModel`）：每种数据占了多少，清一种或全部清掉。 */
@MainActor
@Observable
final class StorageModel {
    let kinds: [LocalDataKind]
    /** 量好的用量；没有的还在量。 */
    private(set) var usage: [LocalDataKind: LocalDataUsage] = [:]
    /** 正在清的（一种，或「全部清除」时所有）。 */
    private(set) var clearing: Set<LocalDataKind> = []

    @ObservationIgnored private let service: LocalDataService

    init(service: LocalDataService) {
        self.service = service
        kinds = service.kinds
    }

    func measureAll() async {
        for kind in kinds { await measure(kind) }
    }

    func clear(_ kind: LocalDataKind) async {
        await run([kind]) { try await self.service.clear(kind) }
    }

    func clearAll() async {
        await run(Set(kinds)) { try await self.service.clearAll() }
    }

    private func run(_ targets: Set<LocalDataKind>, _ block: () async throws -> Void) async {
        guard clearing.isEmpty else { return }
        clearing = targets
        do {
            try await block()
            PulsoMessageCenter.shared.success("storage_cleared")
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "storage_clear_failed")
        }
        clearing = []
        for kind in targets {
            usage[kind] = nil
            await measure(kind)
        }
    }

    private func measure(_ kind: LocalDataKind) async {
        if let value = try? await service.usage(kind) { usage[kind] = value }
    }
}

/**
 * 设置 → 清除本地数据（Android `StorageScreen`）：这台设备上的每个存储一行，显示占用（量的时候显示「-」）；
 * 点一行按住确认后清掉它，「全部清除」清空所有。登录状态不受影响。
 */
public struct StorageView: View {
    @State private var model: StorageModel
    @State private var confirm: PulsoHoldConfirm?

    public init(service: LocalDataService) {
        _model = State(initialValue: StorageModel(service: service))
    }

    public var body: some View {
        List {
            Section {
                ForEach(model.kinds, id: \.self) { kind in
                    Button {
                        guard model.clearing.isEmpty else { return }
                        let label = String(localized: kind.labelResource)
                        confirm = PulsoHoldConfirm(
                            title: localizedFormat("storage_clear_title", label),
                            message: String(localized: (kind.recoverable ? "storage_clear_refetch" : "storage_clear_permanent") as String.LocalizationValue),
                            label: String(localized: "storage_clear_confirm")
                        ) { Task { await model.clear(kind) } }
                    } label: {
                        LabeledContent {
                            Text(verbatim: usageText(model.usage[kind], clearing: model.clearing.contains(kind)))
                        } label: {
                            Label(LocalizedStringKey(kind.labelKeyName), systemImage: kind.symbol)
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Text("storage_intro").textCase(nil)
            }
            Section {
                Button("storage_clear_all", systemImage: "trash", role: .destructive) {
                    guard model.clearing.isEmpty else { return }
                    let title = String(localized: "storage_clear_all")
                    confirm = PulsoHoldConfirm(title: title, message: String(localized: "storage_clear_all_text"), label: title) {
                        Task { await model.clearAll() }
                    }
                }
            }
        }
        .navigationTitle("settings_storage")
        .task { await model.measureAll() }
        .pulsoHoldConfirm($confirm)
    }

    /** 「120 条 · 3.4 MB」「空」，量 / 清的时候是「-」。 */
    private func usageText(_ usage: LocalDataUsage?, clearing: Bool) -> String {
        guard let usage, !clearing else { return "-" }
        let count = usage.count ?? 0
        let bytes = usage.bytes ?? 0
        if count == 0, bytes == 0 { return String(localized: "storage_usage_empty") }
        return [
            count > 0 ? localizedFormat("storage_usage_items", count) : nil,
            bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

extension LocalDataKind {
    var labelKeyName: String {
        switch self {
        case .chatMessages: "storage_kind_chat_messages"
        case .conversations: "storage_kind_conversations"
        case .notifications: "storage_kind_notifications"
        case .socialConnections: "storage_kind_social_connections"
        case .friendRequests: "storage_kind_friend_requests"
        case .profileCards: "storage_kind_profile_cards"
        case .images: "storage_kind_images"
        case .chatWallpapers: "storage_kind_chat_wallpapers"
        case .drafts: "storage_kind_drafts"
        }
    }

    var labelResource: String.LocalizationValue { String.LocalizationValue(labelKeyName) }

    var symbol: String {
        switch self {
        case .chatMessages: "bubble.left.and.bubble.right"
        case .conversations: "text.bubble"
        case .notifications: "bell"
        case .socialConnections: "person.2"
        case .friendRequests: "person.badge.plus"
        case .profileCards: "person.text.rectangle"
        case .images: "photo"
        case .chatWallpapers: "photo.on.rectangle"
        case .drafts: "square.and.pencil"
        }
    }
}
