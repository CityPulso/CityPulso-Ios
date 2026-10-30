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
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(tab: WalletTab = .memberships) {
        _model = State(initialValue: WalletModel(tab: tab))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    entry("creditcard", "wallet_payment_methods", "wallet_payment_methods_hint", .paymentMethods)
                    entry("building.columns", "wallet_payment_accounts", "wallet_payment_accounts_hint", .paymentAccounts)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Picker(selection: $model.tab) {
                    Text("wallet_tab_memberships").tag(WalletTab.memberships)
                    Text("wallet_tab_bundles").tag(WalletTab.bundles)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            switch model.tab {
            case .memberships: membershipsSection
            case .bundles: bundlesSection
            }
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

    /** 卡片本身就是入口，用按钮推页面，列表不会再在外面加一个箭头。 */
    private func entry(_ systemImage: String, _ title: LocalizedStringKey, _ hint: LocalizedStringKey, _ route: LoopRoute) -> some View {
        Button { shell?.push(route) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(Color.accentColor)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var membershipsSection: some View {
        Section {
            Picker(selection: $model.membershipsTab) {
                Text("my_memberships_tab_cards").tag(MyMembershipsTab.cards)
                Text("my_memberships_tab_pending").tag(MyMembershipsTab.pending)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("my_memberships_subtitle")
        }
        if model.membershipsTab == .cards {
            let list = model.memberships
            if list.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = list.error {
                PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
            } else if list.isEmpty {
                ContentUnavailableView {
                    Label("my_memberships_empty_title", systemImage: "person.text.rectangle")
                } description: {
                    Text("my_memberships_empty_body")
                } actions: {
                    Button("my_memberships_empty_cta") { shell?.open(.explore) }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(list.items, id: \.id) { membership in
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
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear { if membership.id == list.items.last?.id { list.loadMore() } }
                }
            }
        } else {
            let list = model.waiting
            if list.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = list.error {
                PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
            } else if list.isEmpty {
                ContentUnavailableView {
                    Label("my_memberships_pending_empty", systemImage: "hourglass")
                } description: {
                    Text("my_memberships_pending_hint")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(list.items, id: \.id) { order in
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
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear { if order.id == list.items.last?.id { list.loadMore() } }
                }
            }
        }
    }

    @ViewBuilder
    private var bundlesSection: some View {
        Section {
            Picker(selection: $model.bundlesTab) {
                Text("my_bundles_tab_active").tag(BundleCabinetTab.active)
                Text("my_bundles_tab_pending").tag(BundleCabinetTab.pending)
                Text("my_bundles_tab_all").tag(BundleCabinetTab.all)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("my_bundles_subtitle")
        }
        let list = model.bundles
        if list.isLoading {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
        } else if list.isEmpty {
            ContentUnavailableView {
                Label(emptyKey, systemImage: "ticket")
            } description: {
                Text("my_bundles_empty_body")
            } actions: {
                Button("my_bundles_browse") { shell?.open(.explore) }.buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(list.items, id: \.id) { bundle in
                NavigationLink(value: LoopRoute.myBundle(bundleId: bundle.id)) {
                    BundleTicket(item: bundle, coverURL: model.coverURL(bundle.venueCoverImageId))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onAppear { if bundle.id == list.items.last?.id { list.loadMore() } }
            }
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
