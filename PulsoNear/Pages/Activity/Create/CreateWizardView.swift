import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 四步表单的外壳（Android `CreateWizardChrome` + `<ActivityType>Form`）：顶部步骤条（做完的步骤可点回去），中间当前步，
 * 底部错误提示和上一步 / 下一步；最后一步的主按钮是发布。所有活动类型共用，活动类型之间只差「活动设置」里的那一块。
 */
struct CreateWizardView: View {
    let model: CreateActivityModel

    @State private var pickingLocation = false

    private var step: CreateWizardStep { model.draft.wizardStep }
    private var isFirst: Bool { step == CreateWizardStep.allCases.first }
    private var isLast: Bool { step == .publish }

    var body: some View {
        VStack(spacing: 0) {
            CreateStepBar(current: step, enabled: !model.isSubmitting) { model.goToStep($0) }
            Divider()
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.labelKey).font(.title2.bold())
                        Text(step.hintKey).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                }
                switch step {
                case .basics: CreateStepBasics(model: model)
                case .whenWhere: CreateStepWhenWhere(model: model) { pickingLocation = true }
                case .settings: CreateStepSettings(model: model)
                case .publish: CreateStepPublish(model: model)
                }
            }
            .disabled(model.isSubmitting)
            .scrollDismissesKeyboard(.interactively)
            .animation(.default, value: step)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $pickingLocation) {
            NavigationStack {
                LocationPickView(showsClose: true, onConfirmed: { Task { await model.applyPickedLocation() } })
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let message = model.formError?.text ?? model.submitError {
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 12))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack(spacing: 12) {
                if !isFirst {
                    Button { model.previousStep() } label: { Text("create_flow_previous").frame(maxWidth: .infinity) }
                        .buttonStyle(.pulso(.soft))
                        .tint(.secondary)
                        .disabled(model.isSubmitting)
                }
                Button {
                    if isLast {
                        Task { await model.submit() }
                    } else {
                        model.nextStep()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if model.isSubmitting { ProgressView() }
                        Text((model.isSubmitting ? "create_submitting" : isLast ? "create_flow_publish" : "create_flow_next") as LocalizedStringKey)
                        if !isLast { Image(systemName: "chevron.right") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pulso())
                .layoutPriority(1)
                .disabled(model.isSubmitting)
            }
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
    }
}

/** 编号圆点连成一条线，每步名字在圆点下；做完的步骤显示对勾、可以点回去。 */
private struct CreateStepBar: View {
    let current: CreateWizardStep
    let enabled: Bool
    let onSelect: (CreateWizardStep) -> Void

    var body: some View {
        let steps = CreateWizardStep.allCases
        let currentIndex = steps.firstIndex(of: current) ?? 0
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let done = index < currentIndex
                let active = index == currentIndex
                Button { onSelect(step) } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 0) {
                            line(visible: index > 0, reached: index <= currentIndex)
                            ZStack {
                                Circle().fill(done || active ? Color.accentColor : Color(.secondarySystemFill))
                                if done {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                } else {
                                    Text(verbatim: "\(index + 1)").font(.caption.bold()).foregroundStyle(active ? Color.white : Color.secondary)
                                }
                            }
                            .frame(width: 28, height: 28)
                            line(visible: index < steps.count - 1, reached: index < currentIndex)
                        }
                        Text(step.labelKey)
                            .font(.caption2.weight(active ? .bold : .regular))
                            .foregroundStyle(active ? Color.accentColor : Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!done || !enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private func line(visible: Bool, reached: Bool) -> some View {
        Rectangle()
            .fill(!visible ? Color.clear : reached ? Color.accentColor : Color(.separator))
            .frame(height: 2)
    }
}

/* ------------------------------ 共用的表单行 ------------------------------ */

/** 标签在上的字段：必填带红色 *，选填在标签行末尾标「选填」（Android `WizardField`）。 */
struct WizardField<Content: View>: View {
    let label: LocalizedStringKey
    var required = false
    var optional = false
    var hint: Text?
    var systemImage: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    (Text(label) + (required ? Text(verbatim: " *").foregroundStyle(.red) : Text(verbatim: "")))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if optional { Text("create_flow_optional").font(.caption).foregroundStyle(.secondary) }
                }
                content
                if let hint { hint.font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/** 标签（和说明）在左，− 数值 + 在右（Android `WizardCounter`）。 */
struct WizardCounter: View {
    let label: LocalizedStringKey
    let value: String
    let minimum: Int
    var maximum = 999
    var hint: LocalizedStringKey?
    var systemImage: String?
    let onChange: (String) -> Void

    var body: some View {
        let number = Int(value) ?? minimum
        Stepper {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Text(verbatim: value).font(.headline).monospacedDigit()
            }
        } onIncrement: {
            if number < maximum { onChange(String(number + 1)) }
        } onDecrement: {
            if number > minimum { onChange(String(number - 1)) }
        }
    }
}
