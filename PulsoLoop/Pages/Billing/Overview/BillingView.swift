import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 账单（Android `BillingViewModel`）：先选运动，再分「我主持的」收款清单 / 「我的付款」，各带一个状态筛选。
 * 换身份、运动或筛选都从第一页重拉；只拉当前显示的那张列表。
 */
@MainActor
@Observable
final class BillingModel {
    var sport = LoopSport.badminton {
        didSet { if sport != oldValue { reload() } }
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
    @ObservationIgnored private let services = Container.shared.loopSportServices()
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
        guard signedIn, sport.available, let service = services[sport] else { return }
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

/**
 * 账单（Android `BillingScreen`）：一级运动标签 → 二级「我主持的 | 我的付款」+ 行尾状态下拉 → 卡片列表。
 * 主持的卡片点进收款清单、日历按钮看活动；我的付款点进活动。
 */
struct BillingView: View {
    @State private var model = BillingModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            PulsoUnderlineTabRow(LoopSport.allCases, selection: $model.sport, image: { Image($0.iconAsset) }) { Text($0.labelKey) }
            if !model.sport.available {
                PulsoEmptyState(Text(model.sport.labelKey), description: Text("coming_soon_subtitle"), style: .comingSoon)
            } else {
                PulsoHighlightTabRow(BillingScope.allCases, selection: $model.scope, label: { Text($0.labelKey) }) {
                    switch model.scope {
                    case .hosted:
                        PulsoMenuSelect(BillingHostedFilter.allCases, selection: $model.hostedFilter, size: .small) { Text($0.labelKey) }
                    case .mine:
                        PulsoMenuSelect(BillingMineFilter.allCases, selection: $model.mineFilter, size: .small) { Text($0.labelKey) }
                    }
                }
                .padding(.vertical, PulsoSpace.s1)
                .padding(.trailing, PulsoSpace.s2)
                list
            }
        }
        .navigationTitle("shell_dest_billing")
        .task { await model.observe() }
    }

    @ViewBuilder
    private var list: some View {
        if let hosted = model.hosted {
            PulsoPagedList(list: hosted, observe: false, emptyTitle: "shell_billing_hosted_empty", emptyBody: "shell_billing_hosted_empty_hint") {
                EmptyView()
            } row: { row in
                HostedChecklistRow(row: row, sport: model.sport)
            }
            .task(id: model.generation) { await model.observeList() }
        } else if let mine = model.mine {
            PulsoPagedList(list: mine, observe: false, emptyTitle: "shell_billing_mine_empty", emptyBody: "shell_billing_mine_empty_hint") {
                EmptyView()
            } row: { row in
                NavigationLink(value: LoopRoute.event(sport: model.sport, eventId: row.eventId)) {
                    MyChecklistItemRow(row: row)
                }
            }
            .task(id: model.generation) { await model.observeList() }
        } else {
            PulsoEmptyState(
                Text((model.scope == .hosted ? "shell_billing_hosted_empty" : "shell_billing_mine_empty") as LocalizedStringKey),
                description: Text((model.scope == .hosted ? "shell_billing_hosted_empty_hint" : "shell_billing_mine_empty_hint") as LocalizedStringKey)
            )
        }
    }
}

/** 我主持的一张收款清单：状态图标、标题、球馆 / 时间、结清状态；点卡片进清单，日历按钮看活动。 */
private struct HostedChecklistRow: View {
    let row: HostedChecklistRowUi
    let sport: LoopSport

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        HStack(spacing: PulsoSpace.s4) {
            NavigationLink(value: LoopRoute.checklist(sport: sport, eventId: row.eventId)) {
                HStack(spacing: PulsoSpace.s4) {
                    Image(systemName: row.isAllSettled ? "checkmark.circle.fill" : "list.clipboard")
                        .font(.title3)
                        .foregroundStyle(row.isAllSettled ? palette.accent.step(9) : palette.error)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        Text(verbatim: row.venueName ?? row.startsAt)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                        Text((row.isAllSettled ? "shell_billing_status_settled" : "shell_billing_status_unsettled") as LocalizedStringKey)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(row.isAllSettled ? palette.accent.step(9) : palette.error)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NavigationLink(value: LoopRoute.event(sport: sport, eventId: row.eventId)) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(palette.text)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(Text("shell_billing_view_event"))
        }
    }
}

/** 我的一条付款：标题、球馆 / 时间、金额；右边已付 / 未付。 */
private struct MyChecklistItemRow: View {
    let row: MyChecklistItemRowUi

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        HStack(spacing: PulsoSpace.s4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(verbatim: row.venueName ?? row.startsAt)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                if let amount = row.priceAmount {
                    Text(verbatim: formatMoney(amount, currency: row.currency))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text((row.paid ? "shell_billing_status_paid" : "shell_billing_status_unpaid") as LocalizedStringKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.paid ? palette.accent.step(9) : palette.error)
        }
    }
}
