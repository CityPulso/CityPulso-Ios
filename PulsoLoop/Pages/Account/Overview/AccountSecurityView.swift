import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 账户安全（对应 Android `AccountSecurityScreen`）：登录与恢复、安全、账户三组区块。
 * 每行是图标 + 120pt 标签列 + 当前值（Android `HubValueRow`），还没开放的项点了提示即将推出。
 */
struct AccountSecurityView: View {
    @State private var emails = EmailListModel()
    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: PulsoSpace.s4) {
                PulsoSection("account_security_section_access") {
                    NavigationLink(value: LoopRoute.emails) {
                        valueRow("envelope", "account_security_emails", Text(verbatim: emailSummary))
                    }
                    .buttonStyle(.pulsoRow)
                    NavigationLink(value: LoopRoute.changePassword) {
                        valueRow("lock", "account_security_password", Text("account_security_password_enabled"))
                    }
                    .buttonStyle(.pulsoRow)
                    comingSoon {
                        valueRow("phone", "account_security_phone", Text("account_security_phone_not_added"), placeholder: true)
                    }
                    comingSoon {
                        valueRow("arrow.right.to.line", "account_security_signin_methods", Text("account_security_signin_methods_password"))
                    }
                }

                PulsoSection("account_security_section_security") {
                    comingSoon {
                        valueRow("checkmark.shield", "account_security_two_step", Text("account_security_two_step_off"))
                    }
                    comingSoon {
                        valueRow("laptopcomputer.and.iphone", "account_security_sessions", Text("account_security_sessions_placeholder"), placeholder: true)
                    }
                }

                PulsoSection("account_security_section_account") {
                    comingSoon {
                        PulsoSectionRow("account_security_delete_account", systemImage: "exclamationmark.triangle", tint: palette.error)
                    }
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("account_security_title")
        .refreshable { await emails.load() }
        .task { await emails.observe() }
    }

    private var emailSummary: String {
        guard let primary = emails.primaryEmail else {
            return emails.emails == nil ? "" : String(localized: "account_security_emails_none")
        }
        return primary.isPrimary ? localizedFormat("account_security_emails_primary_summary", primary.email) : primary.email
    }

    /** 图标 + 120pt 标签 + 值（[placeholder] 的值用次要字色）+ 箭头。 */
    private func valueRow(_ systemImage: String, _ label: LocalizedStringKey, _ value: Text, placeholder: Bool = false) -> some View {
        HStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 20, height: 20)
                .padding(.trailing, PulsoSpace.s3)
            Text(label)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
                .padding(.trailing, PulsoSpace.s3)
            value
                .foregroundStyle(placeholder ? palette.secondaryText : palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
        }
        .font(.body)
        .padding(PulsoSpace.s4)
        .contentShape(Rectangle())
    }

    private func comingSoon(@ViewBuilder _ label: () -> some View) -> some View {
        Button {
            PulsoMessageCenter.shared.info("account_security_coming_soon")
        } label: {
            label()
        }
        .buttonStyle(.pulsoRow)
    }
}
