import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 收款清单页（Android `<ActivityType>ChecklistScreen`）：总数 / 已付 / 未付，主办可全部结清、催缴；每人一行，
 * 主办右滑标记已付 / 未付、左滑提醒，或者用 ⋯ 菜单。右上角回到活动。
 */
struct ChecklistView: View {
    let activityType: NearActivityKind
    let activityId: String
    @State private var model: ChecklistModel

    init(activityType: NearActivityKind, activityId: String) {
        self.activityType = activityType
        self.activityId = activityId
        _model = State(initialValue: ChecklistModel(activityType: activityType, activityId: activityId))
    }

    var body: some View {
        content
            .navigationTitle(Text("checklist_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: NearRoute.activity(activityType: activityType, activityId: activityId)) { Image(systemName: "calendar") }
                        .accessibilityLabel(Text("checklist_open_event"))
                }
            }
            .task { await model.observe() }
            .refreshable { model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if model.page.data == nil, model.page.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.page.data == nil, let error = model.page.error {
            PulsoLoadErrorView(error) { model.refresh() }
        } else {
            List {
                Section { hero }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if model.isHost {
                    Section { actions }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                if model.items.isEmpty {
                    ContentUnavailableView {
                        Label("checklist_empty", systemImage: "calendar")
                    } description: {
                        Text("checklist_empty_hint")
                    }
                } else {
                    Section {
                        ForEach(model.items) { item in
                            ChecklistRow(model: model, item: item)
                        }
                    } header: {
                        if model.isHost { Text("checklist_swipe_hint").textCase(nil) }
                    }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("checklist_title").font(.subheadline.bold()).foregroundStyle(Color.accentColor)
            } icon: {
                Image(systemName: "checklist")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: .circle)
            }
            Text("checklist_subtitle").font(.body).foregroundStyle(.secondary)
            if model.page.data?.isAllSettled == true {
                Text("checklist_all_settled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
            }
            HStack(spacing: 8) {
                stat(localizedFormat("checklist_stat_total", model.items.count), tint: .primary, background: AnyShapeStyle(.fill.tertiary))
                stat(localizedFormat("checklist_stat_paid", model.paidCount), tint: paidGreen, background: AnyShapeStyle(paidGreen.opacity(0.15)))
                stat(
                    localizedFormat("checklist_stat_unpaid", model.unpaidCount),
                    tint: model.unpaidCount > 0 ? .red : .primary,
                    background: model.unpaidCount > 0 ? AnyShapeStyle(Color.red.opacity(0.12)) : AnyShapeStyle(.fill.tertiary)
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.06), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor.opacity(0.25)))
    }

    private func stat(_ text: String, tint: Color, background: AnyShapeStyle) -> some View {
        Text(verbatim: text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(background, in: .rect(cornerRadius: 10))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { Task { await model.settleAll() } } label: {
                Group { if model.isActionInProgress { ProgressView() } else { Text("checklist_settle_all") } }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.pulso())
            .disabled(model.isActionInProgress || model.unpaidCount == 0)
            Button { Task { await model.remindAll() } } label: {
                Label("checklist_remind_all", systemImage: "bell").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pulso(.soft))
            .disabled(model.isActionInProgress || model.remindableIds.isEmpty)
        }
        .controlSize(.large)
    }
}

/** 已付一直是绿色（主题色可能是红 / 橙，看起来像欠款）。 */
private let paidGreen = RadixScale.green.lightStep(11)

/** 一个付款人，像聊天列表一样一行（Android `ChecklistRow`）：主办右滑标记已付 / 未付，左滑提醒，也可以用 ⋯ 菜单。 */
private struct ChecklistRow: View {
    let model: ChecklistModel
    let item: ActivityChecklistEntry

    var body: some View {
        let ready = item.canRemind()
        HStack(spacing: 12) {
            PulsoAvatar(url: model.imageURL(item.avatarImageId), size: 40, systemImage: "person", fallbackText: item.displayName)
            Text(verbatim: item.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "explore_pin_untitled"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text((item.paid ? "checklist_status_paid" : "checklist_status_unpaid") as LocalizedStringKey)
                .font(.caption.weight(.medium))
                .foregroundStyle(item.paid ? paidGreen : Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(item.paid ? paidGreen.opacity(0.15) : Color.red.opacity(0.12), in: .capsule)
            if model.isHost {
                Menu {
                    Button { Task { await model.togglePaid(item) } } label: {
                        Label((item.paid ? "checklist_mark_unpaid" : "checklist_mark_paid") as LocalizedStringKey, systemImage: item.paid ? "circle" : "checkmark.circle")
                    }
                    if !item.paid {
                        Button { Task { await model.remind(item) } } label: {
                            Label((ready ? "checklist_remind" : "checklist_remind_cooldown") as LocalizedStringKey, systemImage: "bell")
                        }
                        .disabled(!ready)
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32)
                }
                .disabled(model.isActionInProgress)
                .accessibilityLabel(Text("checklist_more"))
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if model.isHost {
                Button { Task { await model.togglePaid(item) } } label: {
                    Text((item.paid ? "checklist_mark_unpaid" : "checklist_mark_paid") as LocalizedStringKey)
                }
                .tint(item.paid ? Color.gray : paidGreen)
                .disabled(model.isActionInProgress)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if model.isHost, !item.paid, ready {
                Button { Task { await model.remind(item) } } label: { Text("checklist_remind") }
                    .tint(.accentColor)
                    .disabled(model.isActionInProgress)
            }
        }
    }
}
