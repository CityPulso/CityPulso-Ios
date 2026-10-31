import PulsoLinkCore
import SwiftUI

/**
 * 一页分页列表（Android `ProgramListScaffold` / `pulsoPagingItems`）：一列独立卡片（左右 16、卡片间 8），
 * 每行自动套 [PulsoCard]（行内 NavigationLink 不显示系统箭头）；加载、错误、空状态，滑到底取下一页，下拉刷新。
 */
public struct PulsoPagedList<Item: Identifiable & Sendable, EmptyAction: View, Header: View, Row: View>: View {
    let list: PagedList<Item, Int>
    var observe = true
    let emptyTitle: LocalizedStringKey
    let emptyBody: LocalizedStringKey
    @ViewBuilder let emptyAction: () -> EmptyAction
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Item) -> Row

    public init(
        list: PagedList<Item, Int>,
        observe: Bool = true,
        emptyTitle: LocalizedStringKey,
        emptyBody: LocalizedStringKey,
        @ViewBuilder emptyAction: @escaping () -> EmptyAction,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.list = list
        self.observe = observe
        self.emptyTitle = emptyTitle
        self.emptyBody = emptyBody
        self.emptyAction = emptyAction
        self.header = header
        self.row = row
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: PulsoSpace.s2) {
                header()
                if list.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, PulsoSpace.s8)
                } else if let error = list.error {
                    PulsoLoadErrorView(error) { Task { await list.refresh() } }
                } else if list.isEmpty {
                    PulsoEmptyState(Text(emptyTitle), description: Text(emptyBody)) { emptyAction() }
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
                } else {
                    ForEach(list.items) { item in
                        PulsoCard { row(item).padding(PulsoSpace.s4) }
                            .buttonStyle(.plain)
                            .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
        }
        .refreshable { await list.refresh() }
        .task { if observe { await list.observe() } }
    }
}
