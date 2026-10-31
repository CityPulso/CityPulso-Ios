#if canImport(UIKit)
import SwiftUI
import UIKit

/**
 * 多行输入框，可以切到系统表情键盘（Android 聊天输入栏的表情面板）：`emoji` 为真时换成表情键盘，最近使用、
 * 退格都由系统键盘提供。高度随内容长到 `maxLines` 行，再多就在框里滚动。
 */
public struct PulsoEmojiTextView: UIViewRepresentable {
    @Binding private var text: String
    @Binding private var focused: Bool
    private let emoji: Bool
    private let maxLines: Int

    public init(text: Binding<String>, focused: Binding<Bool>, emoji: Bool, maxLines: Int = 5) {
        _text = text
        _focused = focused
        self.emoji = emoji
        self.maxLines = maxLines
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> EmojiCapableTextView {
        let view = EmojiCapableTextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    public func updateUIView(_ view: EmojiCapableTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if view.wantsEmoji != emoji {
            view.wantsEmoji = emoji
            if view.isFirstResponder { view.reloadInputViews() }
        }
        if focused != view.isFirstResponder {
            let focus = focused
            Task { @MainActor in _ = focus ? view.becomeFirstResponder() : view.resignFirstResponder() }
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: EmojiCapableTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let cap = ceil((uiView.font?.lineHeight ?? 20) * CGFloat(maxLines))
        uiView.isScrollEnabled = fitting.height > cap
        return CGSize(width: width, height: min(fitting.height, cap))
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PulsoEmojiTextView

        init(_ parent: PulsoEmojiTextView) { self.parent = parent }

        public func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        public func textViewDidBeginEditing(_ textView: UITextView) { parent.focused = true }
        public func textViewDidEndEditing(_ textView: UITextView) { parent.focused = false }
    }
}

/** `textInputMode` 返回表情输入法时，系统就弹表情键盘。 */
public final class EmojiCapableTextView: UITextView {
    var wantsEmoji = false

    override public var textInputMode: UITextInputMode? {
        if wantsEmoji, let mode = UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage == "emoji" }) { return mode }
        return super.textInputMode
    }
}
#endif
