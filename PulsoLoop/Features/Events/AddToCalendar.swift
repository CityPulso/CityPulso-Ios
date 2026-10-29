import EventKit
import EventKitUI
import PulsoLinkCore
import SwiftUI

/** 要加进系统日历的一场活动（Android `addEventToCalendar` 的参数）。 */
struct CalendarDraft: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let notes: String?

    /** 开始时间解析不了就不加（Android 同样直接返回）。 */
    init?(title: String, startsAt: String, endsAt: String, location: String?, notes: String?) {
        guard let start = DateTimeFormatters.parseInstant(startsAt) else { return nil }
        self.title = title
        self.start = start
        end = DateTimeFormatters.parseInstant(endsAt) ?? start
        self.location = location.flatMap { $0.isEmpty ? nil : $0 }
        self.notes = notes.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/**
 * 系统的「新建日程」界面，预填活动（Android 用 `ACTION_INSERT` 打开日历 App）。
 * iOS 17+ 的 `EKEventEditViewController` 在系统进程里运行，不需要日历权限，也不用写 Info.plist 用途说明。
 */
struct CalendarEventEditor: UIViewControllerRepresentable {
    let draft: CalendarDraft
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.location = draft.location
        event.notes = draft.notes
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: EKEventEditViewController, context _: Context) {}

    @MainActor
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_: EKEventEditViewController, didCompleteWith _: EKEventEditViewAction) {
            onDone()
        }
    }
}
