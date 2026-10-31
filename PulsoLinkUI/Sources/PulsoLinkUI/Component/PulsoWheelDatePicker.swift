import SwiftUI

/**
 * 日期 / 时间字段：点开后从底部弹出系统滚轮（`.wheel` DatePicker，自带惯性、刻度吸附和边界回弹）（Android `PulsoDateTimeWheelSheet`）。
 * A date or date-time field whose value opens a bottom sheet with the system wheel `DatePicker`; the wheel's inertia,
 * snapping and edge bounce are the system's. Same arguments as `DatePicker`; the pick lands on Done.
 */
public struct PulsoWheelDatePicker<Label: View>: View {
    @Binding private var selection: Date
    private let range: ClosedRange<Date>
    private let components: DatePickerComponents
    private let label: Label

    @State private var presented = false
    @State private var draft = Date.now

    public init(selection: Binding<Date>, in range: ClosedRange<Date> = .distantPast ... .distantFuture, displayedComponents: DatePickerComponents = [.date, .hourAndMinute], @ViewBuilder label: () -> Label) {
        _selection = selection
        self.range = range
        components = displayedComponents
        self.label = label()
    }

    public init(selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute], @ViewBuilder label: () -> Label) {
        self.init(selection: selection, in: range.lowerBound ... .distantFuture, displayedComponents: displayedComponents, label: label)
    }

    public init(selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute], @ViewBuilder label: () -> Label) {
        self.init(selection: selection, in: .distantPast ... range.upperBound, displayedComponents: displayedComponents, label: label)
    }

    public var body: some View {
        LabeledContent {
            Button {
                draft = selection
                presented = true
            } label: {
                Text(selection, format: components.contains(.hourAndMinute) ? .dateTime.month().day().weekday().hour().minute() : .dateTime.year().month().day())
            }
            .buttonStyle(.bordered)
        } label: {
            label
        }
        .sheet(isPresented: $presented) {
            NavigationStack {
                DatePicker(selection: $draft, in: range, displayedComponents: components) { EmptyView() }
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { presented = false } label: { Text("pulso_ui_cancel", bundle: .module) }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                selection = draft
                                presented = false
                            } label: { Text("pulso_ui_done", bundle: .module) }
                        }
                    }
            }
            .presentationDetents([.height(320)])
        }
    }
}

extension PulsoWheelDatePicker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date> = .distantPast ... .distantFuture, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) { Text(titleKey) }
    }
}
