import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 日程（对应 Android `AgendaSidePanel`）：活动（按天分组）/ 场地预订（即将开始 + 过去）两个页签，
 * 底部资料、订场、会员、设置的快捷入口。系统 sheet，从栈底页面左边缘右滑打开。
 */
struct AgendaView: View {
    @State private var model = AgendaModel()
    /** The events tab's time line lights up to the row in the middle once the list stops. */
    @State private var timeline = PulsoTimelineTracker()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    /** 关掉日程后打开的页面（推进当前栈）或底栏页面。 */
    let onOpen: (NearRoute) -> Void
    let onOpenRoot: (ShellDestination) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PulsoUnderlineTabRow([AgendaTab.activities, .spaces], selection: $model.tab) { tab in
                        Text(verbatim: tab == .activities ? localizedFormat("home_agenda_tab_activities_count", model.activityItems.data?.count ?? 0) : localizedFormat("home_agenda_tab_spaces_count", model.bookingItems.data?.count ?? 0))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                content
                footer
            }
            .pulsoTimelineList(timeline)
            .task(id: model.activitiesByDay.flatMap { $0.items.map(\.id) }) { timeline.order = model.activitiesByDay.flatMap { $0.items.map { AnyHashable($0.id) } } }
            .refreshable { await model.refresh() }
            .navigationTitle("home_agenda_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("home_agenda_close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
        }
        .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        let loadable = model.tab == .spaces ? model.bookingItems : model.activityItems
        let past = model.pastBookingItems
        if loadable.data == nil, loadable.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if loadable.data == nil, let error = loadable.error {
            PulsoLoadErrorView(error) { Task { await model.refresh() } }
        } else if (loadable.data ?? []).isEmpty, model.tab == .activities || past.isEmpty {
            empty
        } else if model.tab == .activities {
            ForEach(model.activitiesByDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { item in row(item).pulsoTimelineRow(item.id, tracker: timeline) }
                } header: {
                    HStack {
                        Text(verbatim: dayLabel(group.day))
                        Spacer()
                        if group.day == model.activitiesByDay.first?.day {
                            Button("home_agenda_see_all") { open(root: .calendar) }.font(.footnote)
                        }
                    }
                }
            }
        } else {
            Section {
                ForEach(loadable.data ?? []) { item in row(item) }
            } header: {
                HStack {
                    Text("home_agenda_upcoming_bookings")
                    Spacer()
                    Button("home_agenda_see_all") { open(.calendar(tab: .spaceBookings)) }.font(.footnote)
                }
            }
            if !past.isEmpty {
                Section("home_agenda_past_bookings") {
                    ForEach(past) { item in row(item) }
                }
            }
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        Button {
            dismiss()
            onOpen(item.route)
        } label: {
            HStack(spacing: 12) {
                ActivityTypeCover(url: model.imageURL(item.coverImageId), activityType: item.activityType, iconSize: 24)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    ActivityTitle(title: item.title).font(.subheadline.weight(.semibold))
                    ActivityMeta(systemImage: "clock", text: DateTimeFormatters.sessionDayClockRange(item.startsAt, item.endsAt, locale: locale))
                    ActivityMeta(systemImage: "mappin.and.ellipse", text: item.spaceLabel.map { "\(item.place) · \($0)" } ?? item.place)
                }
                Spacer()
                Image(item.activityType.iconAsset).resizable().frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var empty: some View {
        let spaces = model.tab == .spaces
        PulsoEmptyState(Text(spaces ? "home_agenda_empty_spaces" : "home_agenda_empty"), description: Text(spaces ? "home_agenda_empty_spaces_hint" : "home_agenda_empty_hint"), style: .calendar) {
            if !spaces, model.isPulser {
                Button("shell_empty_action_create") { open(root: .create) }.buttonStyle(.pulso())
            }
            Button(spaces ? "space_bookings_browse" : "shell_empty_action_join") { open(root: .explore) }
        }
    }

    private var footer: some View {
        Section {
            Button { open(root: .profile) } label: { Label("home_agenda_footer_profile", systemImage: "person.crop.circle") }
            Button { open(.calendar(tab: .spaceBookings)) } label: { Label("home_agenda_footer_space_bookings", systemImage: "sportscourt") }
            Button { open(root: .wallet) } label: { Label("home_agenda_footer_memberships", systemImage: "creditcard") }
            Button { open(root: .settings) } label: { Label("home_agenda_footer_settings", systemImage: "gearshape") }
        }
        .foregroundStyle(.primary)
    }

    private func open(_ route: NearRoute) {
        dismiss()
        onOpen(route)
    }

    private func open(root: ShellDestination) {
        dismiss()
        onOpenRoot(root)
    }

    /** 今天 / 明天 / 本地化日期。 */
    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "home_agenda_day_today") }
        if calendar.isDateInTomorrow(day) { return String(localized: "home_agenda_day_tomorrow") }
        return day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).weekday(.abbreviated).locale(locale))
    }
}
