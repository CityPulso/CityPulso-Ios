import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 我的订场（Android `CourtBookingsViewModel`）：先选运动，再分即将开始 / 已结束；换运动或分段都从第一页重拉。 */
@MainActor
@Observable
final class CourtBookingsModel {
    var sport = VenueSport.badminton {
        didSet { if sport != oldValue { reload() } }
    }

    var tab = CourtBookingListTab.upcoming {
        didSet { if tab != oldValue { reload() } }
    }

    private(set) var rows: PagedList<CourtBookingRowUi, Int>

    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config
    @ObservationIgnored private let services = Container.shared.venueSportServices()

    init() {
        rows = Container.shared.venueSportServices()[.badminton]!.pageMyBookings(upcoming: true)
    }

    private func reload() {
        rows = services[sport]!.pageMyBookings(upcoming: tab == .upcoming)
    }

    func coverURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }
}

/** 我的订场（Android `CourtBookingsScreen`）：运动分段、即将开始 / 已结束分段，每条订场一行，点进详情。 */
struct CourtBookingsView: View {
    @State private var model = CourtBookingsModel()
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        List {
            Section {
                Picker(selection: $model.sport) {
                    ForEach(VenueSport.allCases, id: \.self) { sport in
                        Text(sport.loopSport.labelKey).tag(sport)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                Picker(selection: $model.tab) {
                    Text("court_bookings_tabs_upcoming").tag(CourtBookingListTab.upcoming)
                    Text("court_bookings_tabs_past").tag(CourtBookingListTab.past)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if model.rows.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if let error = model.rows.error {
                PulsoLoadErrorView(error) { Task { await model.rows.refresh() } }.listRowBackground(Color.clear)
            } else if model.rows.isEmpty {
                ContentUnavailableView {
                    Text((model.tab == .upcoming ? "court_bookings_empty_upcoming" : "court_bookings_empty_past") as LocalizedStringKey)
                } description: {
                    Text("court_bookings_empty_body")
                } actions: {
                    Button("court_bookings_browse") { shell?.open(.explore) }
                        .buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.rows.items) { booking in
                    NavigationLink(value: LoopRoute.courtBooking(sport: model.sport, bookingId: booking.id)) {
                        CourtBookingRow(booking: booking, coverURL: model.coverURL(booking.venueCoverImageId))
                    }
                    .onAppear { if booking.id == model.rows.items.last?.id { model.rows.loadMore() } }
                }
            }
        }
        .navigationTitle("court_bookings_title")
        .refreshable { await model.rows.refresh() }
        .task(id: "\(model.sport.rawValue)-\(model.tab)") { await model.rows.observe() }
    }
}
