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
    @Environment(\.pulsoPalette) private var palette

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

    /** 一级运动标签，二级「我发起的 | 我参加的 | 我的订场」，行尾筛选（灰色方钮，有条件时右上角数字）。 */
    private var header: some View {
        VStack(spacing: 0) {
            PulsoUnderlineTabRow(LoopSport.allCases, selection: $model.sport, image: { Image($0.iconAsset) }) { Text($0.labelKey) }
            if model.sport.available {
                PulsoHighlightTabRow(model.tabs, selection: $model.tab, label: { Text($0.labelKey) }) {
                    Button { filterOpen = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(palette.gray.step(12))
                            .frame(width: PulsoControlSize.compact.height, height: PulsoControlSize.compact.height)
                            .background(palette.gray.step(3), in: palette.controlShape)
                            .overlay(alignment: .topTrailing) {
                                let count = model.filter.activeCount(model.tab)
                                if count > 0 {
                                    Text(verbatim: "\(count)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, PulsoSpace.s1)
                                        .background(palette.error, in: Capsule())
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(.pulsoPressBounce)
                    .accessibilityLabel(Text("activity_filter_title"))
                }
                .padding(.vertical, PulsoSpace.s1)
                .padding(.trailing, PulsoSpace.s2)
            }
        }
        .background(palette.background)
    }

    @ViewBuilder
    private var content: some View {
        contentBody
            // 左右滑动换标签（横向为主才算，不挡上下滚动）。
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                    withAnimation { model.swipe(forward: dx < 0) }
                }
            )
    }

    @ViewBuilder
    private var contentBody: some View {
        if !model.sport.available {
            PulsoEmptyState(Text(model.sport.labelKey), description: Text("coming_soon_subtitle"), style: .comingSoon)
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
            PulsoEmptyState(Text("profile_activity_empty"), description: Text("profile_activity_hosted_empty_hint"), style: .calendar) {
                Button("shell_empty_action_create") { shell?.open(.create) }.buttonStyle(.pulso())
            }
        case .joined:
            let waitlist = model.filter.joined == .waitlisted
            PulsoEmptyState(
                Text(waitlist ? "shell_home_queues_empty" : "profile_activity_empty"),
                description: Text(waitlist ? "shell_home_queues_empty_hint" : "profile_activity_joined_empty_hint"),
                style: .calendar
            ) {
                Button("shell_empty_action_join") { shell?.open(.explore) }.buttonStyle(.pulso())
                if model.isPulser, !waitlist {
                    Button("shell_empty_action_create") { shell?.open(.create) }.buttonStyle(.pulso(.outline, tone: .gray))
                }
            }
        case .courtBookings:
            PulsoEmptyState(
                Text(model.filter.bookings == .past ? "court_bookings_empty_past" : "court_bookings_empty_upcoming"),
                description: Text("court_bookings_empty_body"),
                style: .calendar
            ) {
                Button("court_bookings_browse") { shell?.open(.explore) }.buttonStyle(.pulso())
            }
        }
    }
}
