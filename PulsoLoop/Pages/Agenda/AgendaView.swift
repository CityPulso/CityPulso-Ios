import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 日程（对应 Android `AgendaSidePanel`）：活动（按天分组）/ 场地预订（即将开始 + 过去）两个页签，
 * 底部资料、订场、会员、设置的快捷入口。系统 sheet，从栈底页面左边缘右滑打开。
 */
struct AgendaView: View {
    @State private var model = AgendaModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    /** 关掉日程后打开的页面（推进当前栈）或底栏页面。 */
    let onOpen: (LoopRoute) -> Void
    let onOpenRoot: (ShellDestination) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("home_agenda_title", selection: $model.tab) {
                        Text(verbatim: localizedFormat("home_agenda_tab_events_count", model.eventItems.data?.count ?? 0)).tag(AgendaTab.events)
                        Text(verbatim: localizedFormat("home_agenda_tab_courts_count", model.bookingItems.data?.count ?? 0)).tag(AgendaTab.courts)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                content
                footer
            }
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
        let loadable = model.tab == .courts ? model.bookingItems : model.eventItems
        let past = model.pastBookingItems
        if loadable.data == nil, loadable.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if loadable.data == nil, let error = loadable.error {
            PulsoLoadErrorView(error) { Task { await model.refresh() } }
        } else if (loadable.data ?? []).isEmpty, model.tab == .events || past.isEmpty {
            empty
        } else if model.tab == .events {
            ForEach(model.eventsByDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { item in row(item) }
                } header: {
                    HStack {
                        Text(verbatim: dayLabel(group.day))
                        Spacer()
                        if group.day == model.eventsByDay.first?.day {
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
                    Button("home_agenda_see_all") { open(.calendar(tab: .courtBookings)) }.font(.footnote)
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
                SportCover(url: model.imageURL(item.coverImageId), sport: item.sport, iconSize: 24)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    EventTitle(title: item.title).font(.subheadline.weight(.semibold))
                    EventMeta(systemImage: "clock", text: DateTimeFormatters.sessionDayClockRange(item.startsAt, item.endsAt, locale: locale))
                    EventMeta(systemImage: "mappin.and.ellipse", text: item.courtLabel.map { "\(item.place) · \($0)" } ?? item.place)
                }
                Spacer()
                Image(item.sport.iconAsset).resizable().frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var empty: some View {
        let courts = model.tab == .courts
        ContentUnavailableView {
            Label(courts ? "home_agenda_empty_courts" : "home_agenda_empty", systemImage: courts ? "sportscourt" : "calendar")
        } description: {
            Text(courts ? "home_agenda_empty_courts_hint" : "home_agenda_empty_hint")
        } actions: {
            if !courts, model.isPulser {
                Button("shell_empty_action_create") { open(root: .create) }.buttonStyle(.borderedProminent)
            }
            Button(courts ? "court_bookings_browse" : "shell_empty_action_join") { open(root: .explore) }
        }
    }

    private var footer: some View {
        Section {
            Button { open(root: .profile) } label: { Label("home_agenda_footer_profile", systemImage: "person.crop.circle") }
            Button { open(.calendar(tab: .courtBookings)) } label: { Label("home_agenda_footer_court_bookings", systemImage: "sportscourt") }
            Button { open(root: .wallet) } label: { Label("home_agenda_footer_memberships", systemImage: "creditcard") }
            Button { open(root: .settings) } label: { Label("home_agenda_footer_settings", systemImage: "gearshape") }
        }
        .foregroundStyle(.primary)
    }

    private func open(_ route: LoopRoute) {
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
