import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 赛事页（Android `TournamentsViewModel`）：公开赛事，按标题 / 球馆搜索，只看一个运动（nil = 全部）。 */
@MainActor
@Observable
final class TournamentsModel {
    var search = ""
    var sport: TournamentSport? { didSet { if sport != oldValue { reload() } } }
    private(set) var tournaments: PagedList<TournamentItem, Int>
    /** 换搜索词或运动时加一，页面用它重启列表的 `.task`。 */
    private(set) var generation = 0

    @ObservationIgnored @Injected(\.tournamentService) private var service
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private var appliedSearch = ""

    init() {
        tournaments = Container.shared.tournamentService().pagePublic(search: nil, sport: nil)
    }

    func coverURL(_ imageId: String?) -> URL? { ImageURLs.image(imageId, base: config.apiBaseURL) }

    /** 搜索词停 300ms 再搜。 */
    func searchChanged() async {
        try? await Task.sleep(for: .milliseconds(300))
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !Task.isCancelled, trimmed != appliedSearch else { return }
        appliedSearch = trimmed
        reload()
    }

    private func reload() {
        tournaments = service.pagePublic(search: appliedSearch.isEmpty ? nil : appliedSearch, sport: sport)
        generation += 1
    }
}

/**
 * 赛事（Android `TournamentsScreen`，应用托盘里的赛事页）：所有公开赛事，可以搜索，运动标签带图标；搜索框旁边的奖杯进「我的赛事」。
 * 搜索框和运动标签在列表上方固定。
 */
struct TournamentsView: View {
    @State private var model = TournamentsModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        List {
            Section {
                rows
            } header: {
                filters
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .navigationTitle("shell_dest_tournaments")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.tournaments.refresh() }
        .task(id: model.generation) { await model.tournaments.observe() }
        .task(id: model.search) { await model.searchChanged() }
    }

    /** 搜索 +「我的赛事」，一级运动标签（全部 + 各运动），滚动时贴在顶部。 */
    private var filters: some View {
        VStack(spacing: 0) {
            HStack(spacing: PulsoSpace.s2) {
                PulsoSearchField(text: $model.search, prompt: Text("tournament_list_search"))
                // 「我的赛事」是搜索框旁边的图标（Android：作为底栏页时没有顶栏，入口放这里）。
                NavigationLink(value: LoopRoute.myTournaments) {
                    Image(systemName: "trophy")
                        .font(.title3)
                        .foregroundStyle(palette.text)
                        .frame(width: PulsoControlSize.compact.height, height: PulsoControlSize.compact.height)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("tournament_mine_title"))
            }
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
            PulsoUnderlineTabRow([nil] + TournamentSport.allCases.map(Optional.some), selection: $model.sport, image: { $0.map { Image($0.loopSport.iconAsset) } }) { sport in
                Text(sport.map { $0.loopSport.labelKey } ?? "tournament_list_all")
            }
        }
        .background(palette.background)
        .listRowInsets(EdgeInsets())
        .textCase(nil)
    }

    @ViewBuilder
    private var rows: some View {
        let list = model.tournaments
        if list.isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16).fill(.fill.tertiary).aspectRatio(16 / 9, contentMode: .fit)
                    .listRowSeparator(.hidden)
            }
        } else if let error = list.error {
            PulsoLoadErrorView(error) { Task { await list.refresh() } }.listRowSeparator(.hidden)
        } else if list.isEmpty {
            PulsoEmptyState(Text("tournament_list_empty"), description: Text("tournament_list_empty_body"))
                .frame(minHeight: 360)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            ForEach(list.items, id: \.id) { item in
                NavigationLink(value: LoopRoute.tournament(tournamentId: item.id)) {
                    TournamentCard(item: item, coverURL: model.coverURL(item.coverImageId))
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .onAppear { if item.id == list.items.last?.id { list.loadMore() } }
            }
        }
    }
}

/** 海报卡（WEB `TournamentCard`）：封面上是状态，下面标题、日期、球馆、组别 · 报名 · 最低报名费。 */
private struct TournamentCard: View {
    let item: TournamentItem
    let coverURL: URL?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle().fill(Color.accentColor.opacity(0.12))
                    if let coverURL {
                        PulsoRemoteImage(url: coverURL)
                    } else {
                        Image(systemName: "trophy").font(.largeTitle).foregroundStyle(Color.accentColor)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                Text(item.status.labelKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.background.opacity(0.9), in: .capsule)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.title).font(.headline).lineLimit(2)
                if !dates.isEmpty { meta("calendar", dates) }
                if !item.venues.isEmpty { meta("mappin.and.ellipse", item.venues.map(\.venueName).joined(separator: " · ")) }
                if !counts.isEmpty { meta("person.2", counts) }
            }
            .padding(12)
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var dates: String {
        let zone = TimeZone(identifier: item.timezone) ?? .current
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: zone)
        let days = [item.startsAt, item.endsAt].compactMap { DateTimeFormatters.parseInstant($0)?.formatted(style) }
        return NSOrderedSet(array: days).array.compactMap { $0 as? String }.joined(separator: " – ")
    }

    private var counts: String {
        var parts: [String] = []
        if item.divisionCount > 0 {
            parts.append(localizedFormat("tournament_list_divisions", item.divisionCount))
            parts.append(localizedFormat("tournament_list_entries", item.entryCount))
        }
        if let fee = item.minFeeAmount {
            parts.append(fee == 0 ? String(localized: "tournament_list_free_entry") : localizedFormat("tournament_list_from_fee", formatMoney(fee, currency: item.currency, locale: locale)))
        }
        return parts.joined(separator: " · ")
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(verbatim: text).lineLimit(1)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
