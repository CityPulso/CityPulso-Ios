import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 活动中心（日历和资料页共用，对应 Android `activityCenterSection`）：放在 `LazyVStack(pinnedViews: .sectionHeaders)`
 * 里，运动标签和「我发起的 / 我参加的 / 我的订场」+ 筛选按钮吸顶，下面是列表。
 */
struct ActivityCenterSection: View {
    @Bindable var model: ActivityCenterModel
    @State private var filterOpen = false
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        Section {
            content
                .padding(.horizontal)
        } header: {
            header
        }
        .sheet(isPresented: $filterOpen) {
            ActivityFilterSheet(tab: model.tab, filter: model.filter) { model.filter = $0 }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LoopSport.allCases) { sport in
                        let selected = sport == model.sport
                        Button {
                            model.sport = sport
                        } label: {
                            HStack(spacing: 4) {
                                Image(sport.iconAsset).resizable().frame(width: 18, height: 18)
                                Text(sport.labelKey)
                            }
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            if model.sport.available {
                HStack {
                    Picker("activity_filter_title", selection: $model.tab) {
                        ForEach(model.tabs, id: \.self) { Text($0.labelKey).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button { filterOpen = true } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .buttonStyle(.bordered)
                    .badge(model.filter.activeCount(model.tab))
                    .accessibilityLabel(Text("activity_filter_title"))
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if !model.sport.available {
            PulsoComingSoonView(title: model.sport.labelKey, systemImage: "hourglass")
                .frame(minHeight: 320)
        } else if model.isLoadingList {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let error = model.listError, model.isListEmpty {
            PulsoLoadErrorView(error) { Task { await model.refresh() } }
                .frame(minHeight: 320)
        } else if model.isListEmpty {
            empty.frame(minHeight: 320)
        } else {
            switch model.tab {
            case .hosted:
                ForEach(model.hostedItems, id: \.id) { item in
                    NavigationLink(value: LoopRoute.event(sport: item.sport, eventId: item.id)) {
                        EventFeedCard(item: item, badge: .host, imageURL: model.imageURL(item.coverImageId))
                    }
                    .buttonStyle(.plain)
                }
            case .joined:
                ForEach(model.joinedItems, id: \.registrationId) { item in
                    NavigationLink(value: LoopRoute.event(sport: item.sport, eventId: item.id)) {
                        // 我参加的不含我主持的，它们在「我发起的」里。
                        RegistrationRow(item: item, imageURL: model.imageURL(item.coverImageId))
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            case .courtBookings:
                ForEach(model.bookingItems) { booking in
                    if let venueSport = model.venueSport {
                        NavigationLink(value: LoopRoute.courtBooking(sport: venueSport, bookingId: booking.id)) {
                            CourtBookingRow(booking: booking, coverURL: model.imageURL(booking.venueCoverImageId))
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch model.tab {
        case .hosted:
            ContentUnavailableView {
                Label("profile_activity_empty", systemImage: "calendar")
            } description: {
                Text("profile_activity_hosted_empty_hint")
            } actions: {
                Button("shell_empty_action_create") { shell?.open(.create) }.buttonStyle(.borderedProminent)
            }
        case .joined:
            let waitlist = model.filter.joined == .waitlisted
            ContentUnavailableView {
                Label(waitlist ? "shell_home_queues_empty" : "profile_activity_empty", systemImage: "calendar")
            } description: {
                Text(waitlist ? "shell_home_queues_empty_hint" : "profile_activity_joined_empty_hint")
            } actions: {
                Button("shell_empty_action_join") { shell?.open(.explore) }.buttonStyle(.borderedProminent)
                if model.isPulser, !waitlist {
                    Button("shell_empty_action_create") { shell?.open(.create) }
                }
            }
        case .courtBookings:
            ContentUnavailableView {
                Label(model.filter.showEnded ? "court_bookings_empty_past" : "court_bookings_empty_upcoming", systemImage: "sportscourt")
            } description: {
                Text("court_bookings_empty_body")
            } actions: {
                Button("court_bookings_browse") { shell?.open(.explore) }.buttonStyle(.borderedProminent)
            }
        }
    }
}
