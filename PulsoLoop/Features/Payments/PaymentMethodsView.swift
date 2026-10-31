import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 付款方式（对应 Android `PaymentMethodsScreen`）：保存的卡，设为默认、改名、删除（要确认），添加新卡。 */
struct PaymentMethodsView: View {
    @State private var model = PaymentMethodsModel()
    @State private var renaming: PaymentMethodItem?
    @State private var removing: PaymentMethodItem?
    @State private var nickname = ""

    var body: some View {
        List {
            Section {
                if let error = model.methods.error, model.methods.data == nil {
                    PulsoLoadErrorView(error) { model.refresh() }
                } else if model.methods.data == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.items.isEmpty {
                    ContentUnavailableView("payment_methods_empty", systemImage: "creditcard")
                }
                ForEach(model.items, id: \.id) { method in
                    PaymentMethodRow(method: method)
                        .overlay(alignment: .trailing) { if model.busyId == method.id { ProgressView() } }
                        .swipeActions {
                            Button("payment_methods_remove", systemImage: "trash", role: .destructive) { removing = method }
                        }
                        .contextMenu {
                            if !method.isDefault {
                                Button("payment_methods_set_default", systemImage: "star") { Task { await model.setDefault(method.id) } }
                            }
                            Button("payment_methods_rename", systemImage: "pencil") {
                                nickname = method.nickname ?? ""
                                renaming = method
                            }
                            Button("payment_methods_remove", systemImage: "trash", role: .destructive) { removing = method }
                        }
                }
            } footer: {
                Text("payment_methods_intro")
            }
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
