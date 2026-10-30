import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 账单（Android `BillingViewModel`）：先选活动类型，再分「我主持的」收款清单 / 「我的付款」，各带一个状态筛选。
 * 换身份、活动类型或筛选都从第一页重拉；只拉当前显示的那张列表。
 */
@MainActor
@Observable
final class BillingModel {
    var activityType = NearActivityKind.boardGame {
        didSet { if activityType != oldValue { reload() } }
    }

    var scope = BillingScope.hosted {
        didSet { if scope != oldValue { reload() } }
    }

    var hostedFilter = BillingHostedFilter.unsettled {
        didSet { if hostedFilter != oldValue { reload() } }
    }

    var mineFilter = BillingMineFilter.unpaid {
        didSet { if mineFilter != oldValue { reload() } }
    }

    private(set) var signedIn = false
    private(set) var hosted: PagedList<HostedChecklistRowUi, Int>?
    private(set) var mine: PagedList<MyChecklistItemRowUi, Int>?
    /** 每次换列表加一，页面按它重新订阅。 */
    private(set) var generation = 0

    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore
    @ObservationIgnored private let services = Container.shared.nearActivityServices()
    @ObservationIgnored private var profileId: String?

    func observe() async {
        for await session in sessionStore.state.values() {
            let signedIn = !session.currentAccountId.isEmpty && !session.currentProfileId.isEmpty
            guard signedIn != self.signedIn || session.currentProfileId != profileId else { continue }
            self.signedIn = signedIn
            profileId = session.currentProfileId
            reload()
        }
    }

    private func reload() {
        hosted = nil
        mine = nil
        generation += 1
        guard signedIn, activityType.available, let service = services[activityType] else { return }
        switch scope {
        case .hosted: hosted = service.pageHostedChecklists(isAllSettled: hostedFilter == .settled)
        case .mine: mine = service.pageMyPaymentItems(paid: mineFilter == .paid)
        }
    }

    func refresh() async {
        if let hosted { await hosted.refresh() }
        if let mine { await mine.refresh() }
    }

    func observeList() async {
        if let hosted { await hosted.observe() }
        if let mine { await mine.observe() }
    }
}

/** 账单（Android `BillingScreen`）：活动类型标签 → 范围分段 + 状态菜单 → 列表；主持的点进收款清单，我的点进活动。 */
struct BillingView: View {
    @State private var model = BillingModel()

    var body: some View {
        VStack(spacing: 0) {
            activityTypeTabs
            if !model.activityType.available {
                PulsoComingSoonView(title: model.activityType.labelKey, systemImage: "hourglass")
            } else {
                list
            }
        }
        .navigationTitle("shell_dest_billing")
        .task { await model.observe() }
    }

    private var activityTypeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NearActivityKind.allCases, id: \.self) { activityType in
                    let selected = activityType == model.activityType
                    Button {
                        model.activityType = activityType
                    } label: {
                        HStack(spacing: 4) {
                            Image(activityType.iconAsset).resizable().frame(width: 18, height: 18)
                            Text(activityType.labelKey)
                        }
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .capsule)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private var list: some View {
        List {
            Section {
                HStack {
                    Picker(selection: $model.scope) {
                        ForEach(BillingScope.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    switch model.scope {
                    case .hosted:
                        Picker(selection: $model.hostedFilter) {
                            ForEach(BillingHostedFilter.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                    case .mine:
                        Picker(selection: $model.mineFilter) {
                            ForEach(BillingMineFilter.allCases, id: \.self) { Text($0.labelKey).tag($0) }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if let hosted = model.hosted {
                rows(hosted, emptyTitle: "shell_billing_hosted_empty", emptyHint: "shell_billing_hosted_empty_hint") { row in
                    HostedChecklistRow(row: row, activityType: model.activityType)
                }
            } else if let mine = model.mine {
                rows(mine, emptyTitle: "shell_billing_mine_empty", emptyHint: "shell_billing_mine_empty_hint") { row in
                    NavigationLink(value: NearRoute.activity(activityType: model.activityType, activityId: row.activityId)) {
                        MyChecklistItemRow(row: row)
                    }
                }
            } else {
                ContentUnavailableView {
                    Text((model.scope == .hosted ? "shell_billing_hosted_empty" : "shell_billing_mine_empty") as LocalizedStringKey)
                } description: {
                    Text((model.scope == .hosted ? "shell_billing_hosted_empty_hint" : "shell_billing_mine_empty_hint") as LocalizedStringKey)
                }
                .listRowBackground(Color.clear)
            }
        }
        .refreshable { await model.refresh() }
        .task(id: model.generation) { await model.observeList() }
    }

    @ViewBuilder
    private func rows<Item: Identifiable & Codable & Sendable, Row: View>(
        _ list: PagedList<Item, Int>,
        emptyTitle: LocalizedStringKey,
        emptyHint: LocalizedStringKey,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
        } else if list.isEmpty {
            ContentUnavailableView {
                Text(emptyTitle)
            } description: {
                Text(emptyHint)
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(list.items) { item in
                row(item)
                    .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }
}

/** 我主持的一张收款清单：状态图标、标题、门店 / 时间、结清状态；点行进清单，日历按钮看活动。 */
private struct HostedChecklistRow: View {
    let row: HostedChecklistRowUi
    let activityType: NearActivityKind

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink(value: NearRoute.checklist(activityType: activityType, activityId: row.activityId)) {
                HStack(spacing: 14) {
                    Image(systemName: row.isAllSettled ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                        .foregroundStyle(row.isAllSettled ? Color.accentColor : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(verbatim: row.venueName ?? row.startsAt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text((row.isAllSettled ? "shell_billing_status_settled" : "shell_billing_status_unsettled") as LocalizedStringKey)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(row.isAllSettled ? Color.accentColor : .red)
                    }
                    Spacer(minLength: 0)
                }
            }
            NavigationLink(value: NearRoute.activity(activityType: activityType, activityId: row.activityId)) {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("shell_billing_view_activity"))
        }
    }
}

/** 我的一条付款：标题、门店 / 时间、金额；右边已付 / 未付。 */
private struct MyChecklistItemRow: View {
    let row: MyChecklistItemRowUi

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(verbatim: row.venueName ?? row.startsAt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let amount = row.priceAmount {
                    Text(verbatim: formatMoney(amount, currency: row.currency)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text((row.paid ? "shell_billing_status_paid" : "shell_billing_status_unpaid") as LocalizedStringKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.paid ? Color.accentColor : .red)
        }
    }
}
