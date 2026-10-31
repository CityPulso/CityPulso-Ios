import SwiftUI

/**
 * 附近搜索顶栏的双槽（Android `SearchAddressSearchBar`）：左边位置胶囊（强调色 step3 底、定位图标 + 地址），
 * 右边搜索方块（gray4 底）。两格互推：
 * - 点左：已经展开 → 去选位置；否则展开左边。
 * - 点右：已经展开 → 开始输入；否则展开右边（位置收成方块）。
 */
public struct PulsoAddressSearchBar: View {
    let locationLabel: String?
    let unknownLocation: Text
    @Binding var search: String
    let searchHint: Text
    let onOpenLocationPick: () -> Void

    @Environment(\.pulsoPalette) private var palette
    @Environment(\.pulsoControlSize) private var size
    @State private var searchExpanded = false
    @FocusState private var searchFocused: Bool

    public init(
        locationLabel: String?,
        unknownLocation: Text,
        search: Binding<String>,
        searchHint: Text,
        onOpenLocationPick: @escaping () -> Void
    ) {
        self.locationLabel = locationLabel
        self.unknownLocation = unknownLocation
        _search = search
        self.searchHint = searchHint
        self.onOpenLocationPick = onOpenLocationPick
    }

    public var body: some View {
        HStack(spacing: PulsoSpace.s2) {
            Button {
                if searchExpanded {
                    withAnimation(.easeInOut(duration: 0.28)) { searchExpanded = false }
                    searchFocused = false
                } else {
                    onOpenLocationPick()
                }
            } label: {
                HStack(spacing: PulsoSpace.s2) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(palette.accent.step(9))
                    if !searchExpanded {
                        Group {
                            if let locationLabel { Text(verbatim: locationLabel) } else { unknownLocation }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent.step(11))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, searchExpanded ? 0 : PulsoSpace.s4)
                .frame(width: searchExpanded ? size.height : nil, height: size.height)
                .frame(maxWidth: searchExpanded ? size.height : .infinity)
                .background(palette.accent.step(3), in: palette.controlShape)
            }
            .buttonStyle(.plain)

            Button {
                if searchExpanded {
                    searchFocused = true
                } else {
                    withAnimation(.easeInOut(duration: 0.28)) { searchExpanded = true }
                    searchFocused = true
                }
            } label: {
                HStack(spacing: PulsoSpace.s2) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.gray.step(12))
                    if searchExpanded {
                        TextField(text: $search, prompt: searchHint) { searchHint }
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .font(.body)
                            .foregroundStyle(palette.text)
                            .tint(palette.accent.step(9))
                    }
                }
                .padding(.horizontal, searchExpanded ? PulsoSpace.s3 : 0)
                .frame(width: searchExpanded ? nil : size.height, height: size.height)
                .frame(maxWidth: searchExpanded ? .infinity : size.height)
                .background(palette.gray.step(4), in: palette.controlShape)
                .overlay {
                    if searchFocused {
                        palette.controlShape.stroke(palette.accent.step(9), lineWidth: pulsoHairline)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
