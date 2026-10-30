import PulsoLinkCore
import SwiftUI
import UIKit

/** 编辑器能写的颜色（`style="color: #hex"`；API 白名单只收 hex / rgb，和 WEB 同一组）。 */
let richTextColors: [String] = ["#E5484D", "#F76B15", "#F5A524", "#30A46C", "#0090FF", "#6E56CF", "#8B8D98"]

/** 无序 / 有序列表在编辑器里是行首的「• 」/「1. 」，导出时变成 `<ul>` / `<ol>`。 */
private let bulletPrefix = "• "

/**
 * API 给的（已清洗的）HTML ↔ AttributedString（Android 用 compose-rich-editor 同一套引擎读写）。
 * 读：系统 HTML 导入；写：只输出 API 白名单里的 `p / strong / em / u / span style=color / ul / ol / li / br`。
 */
enum RichTextHTML {
    /** 读 HTML；列表项变回编辑器的行首记号，方便接着编辑。 */
    @MainActor
    static func attributed(_ html: String) -> AttributedString {
        guard !html.isEmpty,
              let data = "<meta charset=\"utf-8\"><style>body{font-family:-apple-system;font-size:17px}</style>\(html)".data(using: .utf8),
              let imported = try? NSMutableAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else { return AttributedString(html) }
        // 系统把 `<li>` 写成「\t•\t」或「\t1.\t」。
        let mutable = NSMutableAttributedString(attributedString: imported)
        for (pattern, replacement) in [("\t•\t", bulletPrefix)] {
            var range = (mutable.string as NSString).range(of: pattern)
            while range.location != NSNotFound {
                mutable.replaceCharacters(in: range, with: replacement)
                range = (mutable.string as NSString).range(of: pattern)
            }
        }
        let numbered = try? NSRegularExpression(pattern: "\t(\\d+)\\.\t")
        if let numbered {
            for match in numbered.matches(in: mutable.string, range: NSRange(location: 0, length: (mutable.string as NSString).length)).reversed() {
                let number = (mutable.string as NSString).substring(with: match.range(at: 1))
                mutable.replaceCharacters(in: match.range, with: "\(number). ")
            }
        }
        // 去掉结尾多出来的换行。
        while mutable.string.hasSuffix("\n") {
            mutable.deleteCharacters(in: NSRange(location: (mutable.string as NSString).length - 1, length: 1))
        }
        var out = (try? AttributedString(mutable, including: \.uiKit)) ?? AttributedString(mutable.string)
        // 字体交给 SwiftUI（跟随动态字体），只留粗斜体信息。
        for run in out.runs {
            guard let font = run.uiKit.font else { continue }
            let traits = font.fontDescriptor.symbolicTraits
            var swiftFont = Font.body
            if traits.contains(.traitBold) { swiftFont = swiftFont.bold() }
            if traits.contains(.traitItalic) { swiftFont = swiftFont.italic() }
            out[run.range].uiKit.font = nil
            out[run.range].font = swiftFont
            if let color = run.uiKit.foregroundColor, !Self.isDefaultText(color) {
                out[run.range].foregroundColor = Color(uiColor: color)
            }
            out[run.range].uiKit.foregroundColor = nil
        }
        return out
    }

    /** 写 HTML：每行一个 `<p>`，连续的「• 」行合成 `<ul>`，「N. 」行合成 `<ol>`。 */
    static func html(_ text: AttributedString, context: Font.Context) -> String {
        var lines: [[(String, AttributeContainer)]] = [[]]
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let parts = piece.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty { lines[lines.count - 1].append((part, run.attributes)) }
            }
        }
        var out = ""
        var openList: String?
        for line in lines {
            let raw = line.map(\.0).joined()
            let kind: String? = raw.hasPrefix(bulletPrefix) ? "ul" : (raw.range(of: #"^\d+\. "#, options: .regularExpression) != nil ? "ol" : nil)
            if kind != openList {
                if let openList { out += "</\(openList)>" }
                if let kind { out += "<\(kind)>" }
                openList = kind
            }
            var body = ""
            var dropped = 0
            let prefixLength: Int = switch kind {
            case "ul": bulletPrefix.count
            case "ol": raw.prefix { $0 != " " }.count + 1
            default: 0
            }
            for (segment, attributes) in line {
                var piece = segment
                if dropped < prefixLength {
                    let cut = min(prefixLength - dropped, piece.count)
                    piece = String(piece.dropFirst(cut))
                    dropped += cut
                }
                guard !piece.isEmpty else { continue }
                body += wrap(escape(piece), attributes, context: context)
            }
            out += kind == nil ? "<p>\(body.isEmpty ? "<br>" : body)</p>" : "<li>\(body)</li>"
        }
        if let openList { out += "</\(openList)>" }
        return out
    }

    private static func wrap(_ text: String, _ attributes: AttributeContainer, context: Font.Context) -> String {
        var out = text
        if let font = attributes.font {
            let resolved = font.resolve(in: context)
            if resolved.isBold { out = "<strong>\(out)</strong>" }
            if resolved.isItalic { out = "<em>\(out)</em>" }
        }
        if attributes.underlineStyle != nil { out = "<u>\(out)</u>" }
        if let color = attributes.foregroundColor, let hex = hexString(color) { out = "<span style=\"color: \(hex)\">\(out)</span>" }
        return out
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func hexString(_ color: Color) -> String? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /** 系统默认文字色（黑 / 白）不当作颜色写出去。 */
    private static func isDefaultText(_ color: UIColor) -> Bool {
        var white: CGFloat = 0, alpha: CGFloat = 0
        guard color.getWhite(&white, alpha: &alpha) else { return false }
        return white < 0.05 || white > 0.95
    }

    /** 纯文字长度（计数用）。 */
    static func length(_ text: AttributedString) -> Int {
        text.characters.count
    }
}

/** 帖子 / 评论 / 公告的正文（API 已清洗的 HTML）。 */
struct RichTextBody: View {
    let html: String
    var lineLimit: Int?
    @State private var text = AttributedString()

    var body: some View {
        Text(text)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: html) { text = RichTextHTML.attributed(html) }
    }
}

/**
 * 正文编辑器（Android `RichTextField`）：加粗、斜体、下划线、颜色、无序 / 有序列表，下面是「已用 / 上限」。
 * 调用方拿着 [text]，提交时用 [RichTextHTML.html] 导出。
 */
struct RichTextEditor: View {
    @Binding var text: AttributedString
    let placeholder: LocalizedStringKey
    let maxChars: Int
    var minHeight: CGFloat = 140
    var showCounter = true
    @State private var selection = AttributedTextSelection()
    @State private var paletteOpen = false
    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    tool("bold", "discussion_editor_bold") { toggleTrait(bold: true) }
                    tool("italic", "discussion_editor_italic") { toggleTrait(bold: false) }
                    tool("underline", "discussion_editor_underline") {
                        text.transformAttributes(in: &selection) { container in
                            container.underlineStyle = container.underlineStyle == nil ? .single : nil
                        }
                    }
                    tool("paintpalette", "discussion_editor_color") { paletteOpen.toggle() }
                    tool("list.bullet", "discussion_editor_bullets") { toggleLinePrefix(numbered: false) }
                    tool("list.number", "discussion_editor_numbers") { toggleLinePrefix(numbered: true) }
                }
            }
            if paletteOpen {
                HStack(spacing: 8) {
                    ForEach(richTextColors, id: \.self) { hex in
                        Button {
                            text.transformAttributes(in: &selection) { $0.foregroundColor = Color(hex: hex) }
                            paletteOpen = false
                        } label: {
                            Circle().fill(Color(hex: hex) ?? .primary).frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("discussion_editor_color_reset") {
                        text.transformAttributes(in: &selection) { $0.foregroundColor = nil }
                        paletteOpen = false
                    }
                    .font(.caption)
                }
            }
            ZStack(alignment: .topLeading) {
                if text.characters.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $text, selection: $selection)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
            }
            if showCounter {
                let length = RichTextHTML.length(text)
                Text(verbatim: "\(length) / \(maxChars)")
                    .font(.caption)
                    .foregroundStyle(length > maxChars ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func tool(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 28) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text(label))
    }

    private func toggleTrait(bold: Bool) {
        text.transformAttributes(in: &selection) { container in
            let font = container.font ?? .body
            let resolved = font.resolve(in: fontContext)
            container.font = bold ? font.bold(!resolved.isBold) : font.italic(!resolved.isItalic)
        }
    }

    /** 光标所在的行加上 / 去掉列表记号。 */
    private func toggleLinePrefix(numbered: Bool) {
        let plain = String(text.characters)
        let cursor: String.Index = {
            if case let .insertionPoint(index) = selection.indices(in: text) {
                return plain.index(plain.startIndex, offsetBy: text.characters.distance(from: text.startIndex, to: index))
            }
            if case let .ranges(set) = selection.indices(in: text), let first = set.ranges.first {
                return plain.index(plain.startIndex, offsetBy: text.characters.distance(from: text.startIndex, to: first.lowerBound))
            }
            return plain.endIndex
        }()
        let lineStart = plain[..<cursor].lastIndex(of: "\n").map { plain.index(after: $0) } ?? plain.startIndex
        let line = plain[lineStart...].prefix { $0 != "\n" }
        let offset = plain.distance(from: plain.startIndex, to: lineStart)
        let start = text.characters.index(text.startIndex, offsetBy: offset)
        let existing: String? = line.hasPrefix(bulletPrefix) ? bulletPrefix : line.range(of: #"^\d+\. "#, options: .regularExpression).map { String(line[$0]) }
        if let existing {
            let end = text.characters.index(start, offsetBy: existing.count)
            text.removeSubrange(start ..< end)
            let wanted = numbered ? existing != bulletPrefix : existing == bulletPrefix
            if wanted { return }
        }
        text.insert(AttributedString(numbered ? "1. " : bulletPrefix), at: start)
    }
}

extension Color {
    /** `#RRGGBB` → 颜色。 */
    init?(hex: String) {
        var raw = hex
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
