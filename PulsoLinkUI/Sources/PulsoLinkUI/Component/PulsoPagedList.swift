import PulsoLinkCore
import SwiftUI

/** 一页分页列表（Android `ProgramListScaffold`）：加载、错误、空状态、分页列表（滑到底取下一页），下拉刷新。 */
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
        List {
            header()
            if list.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = list.error {
                PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowBackground(Color.clear)
            } else if list.isEmpty {
                ContentUnavailableView {
                    Text(emptyTitle)
                } description: {
                    Text(emptyBody)
                } actions: {
                    emptyAction()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(list.items) { item in
                    row(item)
                        .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
                }
            }
        }
        .refreshable { await list.refresh() }
        .task { if observe { await list.observe() } }
    }
}
