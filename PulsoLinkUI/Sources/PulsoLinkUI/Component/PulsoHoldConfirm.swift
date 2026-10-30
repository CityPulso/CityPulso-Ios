import SwiftUI

/**
 * 一次要按住确认的危险操作（Android `rememberPulsoHoldConfirm`）：标题、说明、按钮文字和确认后要做的事。
 * 页面持有一个 `PulsoHoldConfirm?`，设上值就弹出，按满后执行并关闭。
 */
public struct PulsoHoldConfirm: Identifiable {
    public let id = UUID()
    let title: String
    let message: String
    let label: String
    let action: () -> Void

    public init(title: String, message: String, label: String, action: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.label = label
        self.action = action
    }
}

extension View {
    /** 把 [request] 显示成按住确认的底部弹层。 */
    public func pulsoHoldConfirm(_ request: Binding<PulsoHoldConfirm?>) -> some View {
        sheet(item: request) { confirm in
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: confirm.title).font(.title3.bold())
                Text(verbatim: confirm.message).foregroundStyle(.secondary)
                PulsoHoldButton(LocalizedStringKey(confirm.label)) {
                    request.wrappedValue = nil
                    confirm.action()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.height(260)])
        }
    }
}
