import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 举报（Android `ReportSheet`）：原因单选 + 补充说明。 */
struct ReportSheet: View {
    let busy: Bool
    let onSubmit: (ForumReportReason, String) -> Void
    @State private var reason = ForumReportReason.allCases.first ?? .fallback
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $reason) {
                        ForEach(ForumReportReason.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text("discussion_report_body")
                }
                Section {
                    TextField("discussion_report_title", text: $detail, prompt: Text("discussion_report_detail_placeholder"), axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("discussion_report_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("discussion_report_submit") { onSubmit(reason, detail.trimmingCharacters(in: .whitespaces)) }
                        .disabled(busy)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/** 选论坛的面板：官方的在前，可以搜（Android `ForumPickerViewModel`）。 */
@MainActor
@Observable
final class ForumPickerModel {
    private static let limit = 40
    var query = "" {
        didSet { schedule() }
    }

    private(set) var forums: [ForumItem] = []
    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var task: Task<Void, Never>?

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    func load() async {
        let search = query.trimmingCharacters(in: .whitespaces)
        if let page = try? await discussion.listForums(ListForumsRequest(limit: Self.limit, search: search.isEmpty ? nil : search, sort: "popular")) {
            forums = page.items
        }
    }

    private func schedule() {
        task?.cancel()
        task = Task {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await load()
        }
    }
}

/**
 * 选论坛（Android `ForumPickerSheet`）：[max] 为 1 时是信息流只看一个论坛；更大时是选发帖去哪些论坛。
 * [lockedIds] 已经发在里面了，不能取消。
 */
struct ForumPickerSheet: View {
    let selected: Set<String>
    let max: Int
    var lockedIds: Set<String> = []
    let onConfirm: (Set<String>) -> Void
    @State private var model = ForumPickerModel()
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            List(model.forums, id: \.id) { forum in
                let checked = picked.contains(forum.id)
                let locked = lockedIds.contains(forum.id)
                Button {
                    if checked { picked.remove(forum.id) } else if max == 1 { picked = [forum.id] } else { picked.insert(forum.id) }
                } label: {
                    HStack(spacing: 10) {
                        PulsoRemoteImage(url: model.imageURL(forum.avatarImageId)).frame(width: 36, height: 36).background(.fill.tertiary).clipShape(.rect(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(verbatim: forum.name).lineLimit(1)
                                ForumBadge(scope: forum.owner.profileScope)
                            }
                            if !forum.sports.isEmpty { ForumTypeTags(types: forum.sports, max: 3) }
                        }
                        Spacer()
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle").foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                }
                .foregroundStyle(.primary)
                .disabled(locked || (!checked && max > 1 && picked.count >= max))
            }
            .searchable(text: $model.query, prompt: Text("discussion_search_forums_placeholder"))
            .navigationTitle(Text(verbatim: max == 1 ? String(localized: "discussion_picker_title_one") : localizedFormat("discussion_picker_title_many", max)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if max == 1 {
                    ToolbarItem(placement: .cancellationAction) { Button("discussion_picker_clear") { onConfirm([]) } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("discussion_picker_confirm") { onConfirm(picked) } }
            }
            .task { await model.load() }
            .onAppear { picked = selected }
        }
    }
}
