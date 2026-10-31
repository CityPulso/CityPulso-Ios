import Factory
import Foundation
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 钱包里会员卡和时长包两个列表（Android `MyMembershipsViewModel` / `MyBundlesViewModel`）。 */
@MainActor
@Observable
final class WalletModel {
    var tab: WalletTab
    var membershipsTab = MyMembershipsTab.cards
    var bundlesTab = BundleCabinetTab.active {
        didSet { if bundlesTab != oldValue { bundles = Container.shared.bundleService().pageMine(bundlesTab.statuses) } }
    }

    /** 服务端已经按「生效中优先，再按最新」排好。 */
    let memberships: PagedList<MyMembership, Int>
    /** 等球馆确认的申请，最新的在前。 */
    let waiting: PagedList<MyMembershipPurchase, Int>
    private(set) var bundles: PagedList<MyBundle, Int>

    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(tab: WalletTab) {
        self.tab = tab
        let membershipService = Container.shared.membershipService()
        memberships = membershipService.pageMyMemberships()
        waiting = membershipService.pageMyWaitingPurchases()
        bundles = Container.shared.bundleService().pageMine(BundleCabinetTab.active.statuses)
    }

    func coverURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }
}

/** 钱包（Android `WalletScreen`）：上面是付款方式、收款账户两个入口，下面「会员卡 / 时长包」两个分段，各自还有子分段。 */
struct WalletView: View {
    @State private var model: WalletModel
    @Environment(\.locale) private var locale
    @Environment(\.pulsoPalette) private var palette
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(tab: WalletTab = .memberships) {
        _model = State(initialValue: WalletModel(tab: tab))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PulsoSpace.s2) {
                HStack(spacing: PulsoSpace.s2) {
                    entry("creditcard", "wallet_payment_methods", "wallet_payment_methods_hint", .paymentMethods)
                    entry("building.columns", "wallet_payment_accounts", "wallet_payment_accounts_hint", .paymentAccounts)
                }
                .padding(.horizontal, PulsoSpace.s4)
                .padding(.top, PulsoSpace.s4)
                .padding(.bottom, PulsoSpace.s3)

                // 一级：会员卡 | 时长包；二级各自的状态。
                PulsoUnderlineTabRow([WalletTab.memberships, .bundles], selection: $model.tab) { tab in
                    Text(tab == .memberships ? "wallet_tab_memberships" : "wallet_tab_bundles")
                }
                switch model.tab {
                case .memberships: memberships
                case .bundles: bundles
                }
            }
            .padding(.bottom, PulsoSpace.s4)
        }
        .navigationTitle("shell_dest_wallet")
        .refreshable {
            switch model.tab {
            case .memberships:
                if model.membershipsTab == .cards { await model.memberships.refresh() } else { await model.waiting.refresh() }
            case .bundles: await model.bundles.refresh()
            }
        }
        .task { await model.memberships.observe() }
        .task { await model.waiting.observe() }
        .task(id: model.bundlesTab) { await model.bundles.observe() }
    }

    /** 入口卡片：强调色图标、标题、一行说明，细边框（Android 钱包顶部两格）。 */
    private func entry(_ systemImage: String, _ title: LocalizedStringKey, _ hint: LocalizedStringKey, _ route: LoopRoute) -> some View {
        Button { shell?.push(route) } label: {
            VStack(alignment: .leading, spacing: PulsoSpace.s1) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(palette.accent.step(9))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text).lineLimit(1)
                Text(hint).font(.caption).foregroundStyle(palette.secondaryText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PulsoSpace.s4)
            .background(palette.panel, in: palette.cardShape)
            .overlay { palette.cardShape.strokeBorder(palette.outlineVariant, lineWidth: pulsoHairline) }
        }
        .buttonStyle(.plain)
    }

    /** 二级标签下面的一行说明。 */
    private func subtitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
    }

    /** 加载 / 出错 / 空 / 一列条目（滑到底取下一页）。 */
    @ViewBuilder
    private func paged<Item: Sendable, ID: Hashable, Empty: View, Row: View>(
        _ list: PagedList<Item, Int>,
        id: KeyPath<Item, ID>,
        @ViewBuilder empty: () -> Empty,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, PulsoSpace.s8)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }
        } else if list.isEmpty {
            empty().frame(minHeight: 360)
        } else {
            ForEach(list.items, id: id) { item in
                row(item)
                    .padding(.horizontal, PulsoSpace.s4)
                    .onAppear { if item[keyPath: id] == list.items.last?[keyPath: id] { list.loadMore() } }
            }
        }
    }

    @ViewBuilder
    private var memberships: some View {
        PulsoHighlightTabRow([MyMembershipsTab.cards, .pending], selection: $model.membershipsTab) { tab in
            Text(tab == .cards ? "my_memberships_tab_cards" : "my_memberships_tab_pending")
        }
        subtitle("my_memberships_subtitle")
        if model.membershipsTab == .cards {
            paged(model.memberships, id: \.id) {
                PulsoEmptyState(Text("my_memberships_empty_title"), description: Text("my_memberships_empty_body")) {
                    Button("my_memberships_empty_cta") { shell?.open(.explore) }.buttonStyle(.pulso())
                }
            } row: { membership in
                NavigationLink(value: LoopRoute.myMembership(membershipId: membership.id)) {
                    MembershipLevelCard(
                        name: membership.venueName,
                        icon: membership.levelIcon,
                        color: membership.levelColor,
                        discountPercent: membership.discountPercent,
                        tag: String(localized: membership.status.labelResource),
                        subtitle: membership.venueAddress,
                        footer: "\(membership.levelName) · \(formatMoney(membership.termPriceAmount, currency: membership.venueCurrency, locale: locale))",
                        portraitURL: model.coverURL(membership.venueCoverImageId),
                        portraitFallback: String(membership.venueName.prefix(1))
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            paged(model.waiting, id: \.id) {
                PulsoEmptyState(Text("my_memberships_pending_empty"), description: Text("my_memberships_pending_hint"))
            } row: { order in
                NavigationLink(value: LoopRoute.myMembershipPurchase(purchaseId: order.id)) {
                    MembershipLevelCard(
                        name: order.venueName,
                        icon: order.levelIcon,
                        color: order.levelColor,
                        discountPercent: order.discountPercent,
                        tag: String(localized: "my_memberships_pending_badge"),
                        subtitle: order.venueAddress,
                        footer: [
                            String(localized: order.kind.pendingLabelResource),
                            order.levelName,
                            formatMoney(order.chargedAmount, currency: order.currency, locale: locale),
                            order.endsAt.map { VenueTime.date($0, timezone: TimeZone.current.identifier, locale: locale) } ?? String(localized: "membership_lifetime"),
                        ].joined(separator: " · "),
                        portraitURL: model.coverURL(order.venueCoverImageId),
                        portraitFallback: String(order.venueName.prefix(1)),
                        muted: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var bundles: some View {
        PulsoHighlightTabRow([BundleCabinetTab.active, .pending, .all], selection: $model.bundlesTab) { tab in
            switch tab {
            case .active: Text("my_bundles_tab_active")
            case .pending: Text("my_bundles_tab_pending")
            case .all: Text("my_bundles_tab_all")
            }
        }
        subtitle("my_bundles_subtitle")
        paged(model.bundles, id: \.id) {
            PulsoEmptyState(Text(emptyKey), description: Text("my_bundles_empty_body")) {
                Button("my_bundles_browse") { shell?.open(.explore) }.buttonStyle(.pulso())
            }
        } row: { bundle in
            NavigationLink(value: LoopRoute.myBundle(bundleId: bundle.id)) {
                BundleTicket(item: bundle, coverURL: model.coverURL(bundle.venueCoverImageId))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyKey: LocalizedStringKey {
        switch model.bundlesTab {
        case .active: "my_bundles_empty_active"
        case .pending: "my_bundles_empty_pending"
        case .all: "my_bundles_empty_all"
        }
    }
}

extension MembershipStatus {
    var labelResource: String.LocalizationValue {
        switch self {
        case .active: "membership_status_active"
        case .expired: "membership_status_expired"
        }
    }
}

extension MembershipLedgerKind {
    /** 待确认申请的类型（新购 / 续费 / 升级）。 */
    var pendingLabelResource: String.LocalizationValue {
        switch self {
        case .purchase: "my_memberships_pending_kind_purchase"
        case .renew: "my_memberships_pending_kind_renew"
        case .upgrade: "my_memberships_pending_kind_upgrade"
        }
    }
}
