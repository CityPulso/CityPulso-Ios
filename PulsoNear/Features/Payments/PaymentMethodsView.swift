import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 付款方式（对应 Android `PaymentMethodsScreen`）：保存的卡，设为默认、改名、删除（要确认），添加新卡。 */
struct PaymentMethodsView: View {
    @State private var model = PaymentMethodsModel()
    @State private var renaming: PaymentMethodItem?
    @State private var removing: PaymentMethodItem?
    @State private var nickname = ""

    @State private var deckOpen = false
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("payment_methods_intro").font(.caption).foregroundStyle(palette.secondaryText)
                if let error = model.methods.error, model.methods.data == nil {
                    PulsoLoadErrorView(error) { model.refresh() }
                } else if model.methods.data == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, PulsoSpace.s8)
                } else if model.items.isEmpty {
                    PulsoEmptyState(Text("payment_methods_empty")).frame(minHeight: 320)
                } else {
                    // 卡片堆：收起时叠着，点一下逐张弹开；打开后每张下面是设为默认 / 改名，长按删除（Android 左滑删除）。
                    PulsoCardStack(items: model.items, id: \.id, expanded: deckOpen, onExpand: { deckOpen = true }) { method in
                        VStack(spacing: PulsoSpace.s2) {
                            PaymentMethodFaceCard(method: method)
                                .contextMenu {
                                    Button("payment_methods_remove", systemImage: "trash", role: .destructive) { removing = method }
                                }
                            if deckOpen {
                                HStack(spacing: PulsoSpace.s2) {
                                    if !method.isDefault {
                                        Button { Task { await model.setDefault(method.id) } } label: {
                                            PulsoButtonLabel("payment_methods_set_default", systemImage: "star", loading: model.busyId == method.id)
                                        }
                                        .buttonStyle(.pulso(.soft, size: .compact, fullWidth: true))
                                    }
                                    Button {
                                        nickname = method.nickname ?? ""
                                        renaming = method
                                    } label: {
                                        Label("payment_methods_rename", systemImage: "pencil")
                                    }
                                    .buttonStyle(.pulso(.soft, tone: .gray, size: .compact, fullWidth: true))
                                    .disabled(model.busyId == method.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(PulsoSpace.s4)
        }
        .refreshable { model.refresh() }
        .navigationTitle("payment_methods_title")
        // Adding a card sits at the bottom of the page.
        .safeAreaInset(edge: .bottom) {
            Button { Task { await model.startAdd() } } label: {
                PulsoButtonLabel("payment_methods_add", systemImage: "plus", loading: model.adding)
            }
            .buttonStyle(.pulso(fullWidth: true))
            .disabled(model.adding)
            .padding(.horizontal, PulsoSpace.s4)
            .padding(.vertical, PulsoSpace.s2)
        }
        .alert("payment_methods_nickname", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("payment_methods_nickname_placeholder", text: $nickname)
            Button("profile_dialog_cancel", role: .cancel) {}
            Button("payment_methods_nickname_save") {
                if let method = renaming { Task { await model.rename(method.id, nickname: nickname) } }
            }
        }
        .alert("payment_methods_remove_title", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { method in
            Button("profile_dialog_cancel", role: .cancel) {}
            Button("payment_methods_remove", role: .destructive) { Task { await model.remove(method.id) } }
        } message: { method in
            Text(verbatim: localizedFormat("payment_methods_remove_message", method.title))
        }
        .task { await model.observe() }
    }
}
