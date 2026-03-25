import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showCopyAlert = false

    private let supportEmail = "support@slidecrop.app"

    var body: some View {
        NavigationStack {
            Form {
                Section("Support") {
                    NavigationLink {
                        PrivacyPolicyView(contactEmail: supportEmail)
                    } label: {
                        Label("Privacy Policy", systemImage: "lock.shield")
                    }

                    Button {
                        composeSupportEmail()
                    } label: {
                        Label("Contact Support", systemImage: "envelope")
                    }
                    .foregroundStyle(.primary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersionText)
                    LabeledContent("Support", value: supportEmail)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SlideCropPageBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Support Email Copied", isPresented: $showCopyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Paste into your mail app: \(supportEmail)")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func composeSupportEmail() {
        let subject = "SlideCrop Support"
        let body = """
        App Version: \(appVersionText)
        Device: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)

        Please describe your issue:
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body

        guard let mailURL = URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            fallbackCopySupportEmail()
            return
        }

        if UIApplication.shared.canOpenURL(mailURL) {
            openURL(mailURL)
        } else {
            fallbackCopySupportEmail()
        }
    }

    private func fallbackCopySupportEmail() {
        UIPasteboard.general.string = supportEmail
        showCopyAlert = true
    }
}

private struct PrivacyPolicyView: View {
    let contactEmail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title2.weight(.semibold))

                Text("Last updated: February 27, 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Group {
                    policySection(
                        title: "What SlideCrop Processes",
                        body: "SlideCrop processes selected photos on-device to detect, straighten, and crop presentation slides."
                    )

                    policySection(
                        title: "Photo Library Access",
                        body: "The app requests photo library access only to read images you choose and to save exported or replaced images."
                    )

                    policySection(
                        title: "Data Collection",
                        body: "SlideCrop does not create accounts, does not run advertising trackers, and does not collect personal analytics data for sale."
                    )

                    policySection(
                        title: "Data Sharing",
                        body: "SlideCrop does not sell your personal information."
                    )

                    policySection(
                        title: "Support",
                        body: "For privacy questions, contact \(contactEmail)."
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SlideCropPageBackground())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
