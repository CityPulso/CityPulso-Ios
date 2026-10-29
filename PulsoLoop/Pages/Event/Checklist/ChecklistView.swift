import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 收款清单页（Android `<Sport>ChecklistScreen`）：总数 / 已付 / 未付，主办可全部结清、催缴、逐个勾选已付。 */
struct ChecklistView: View {
    @State private var model: ChecklistModel

    init(sport: LoopSport, eventId: String) {
        _model = State(initialValue: ChecklistModel(sport: sport, eventId: eventId))
    }

    var body: some View {
        content
            .navigationTitle(Text("checklist_title"))
            .navigationBarTitleDisplayMode(.inline)
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
                stat(localizedFormat("checklist_stat_paid", model.paidCount), tint: .accentColor, background: AnyShapeStyle(Color.accentColor.opacity(0.15)))
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
            .buttonStyle(.glassProminent)
            .disabled(model.isActionInProgress || model.unpaidCount == 0)
            Button { Task { await model.remindAll() } } label: {
                Label("checklist_remind_all", systemImage: "bell").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isActionInProgress || model.remindableIds.isEmpty)
        }
        .controlSize(.large)
    }
}

private struct ChecklistRow: View {
    let model: ChecklistModel
    let item: EventChecklistEntry

    var body: some View {
        HStack(spacing: 10) {
            if model.isHost {
                Button { Task { await model.togglePaid(item) } } label: {
                    Image(systemName: item.paid ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(item.paid ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(model.isActionInProgress)
            }
            PulsoAvatar(url: model.imageURL(item.avatarImageId), size: 40, systemImage: "person", fallbackText: item.displayName)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "explore_pin_untitled"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text((item.paid ? "checklist_status_paid" : "checklist_status_unpaid") as LocalizedStringKey)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.paid ? Color.accentColor : Color.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(item.paid ? Color.accentColor.opacity(0.15) : Color.red.opacity(0.12), in: .capsule)
            }
            Spacer(minLength: 0)
            if model.isHost, !item.paid {
                let ready = item.canRemind()
                Button { Task { await model.remind(item) } } label: {
                    Label((ready ? "checklist_remind" : "checklist_remind_cooldown") as LocalizedStringKey, systemImage: "bell")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isActionInProgress || !ready)
            }
        }
    }
}
