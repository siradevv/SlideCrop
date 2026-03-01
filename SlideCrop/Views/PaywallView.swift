import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var purchaseManager: PurchaseManager

    let remainingFreeSaves: Int
    let requestedCount: Int

    @State private var isWorking = false
    @State private var message: String?
    @State private var heroVisible = false

    var body: some View {
        NavigationStack {
            ZStack {
                SlideCropPageBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        HeroCropIconView()
                            .frame(height: 190)
                            .padding(.horizontal, 18)
                            .scaleEffect(heroVisible ? 1 : 0.96)
                            .opacity(heroVisible ? 1 : 0)
                            .animation(.easeOut(duration: 0.45), value: heroVisible)

                        VStack(spacing: 10) {
                            Text("Unlock Unlimited")
                                .font(.system(size: 35, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            Text(paywallMessage)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18)
                        }
                        .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            featureRow("infinity.circle.fill", "Unlimited saves forever")
                            featureRow("photo.on.rectangle.angled", "Save as New Images")
                            featureRow("arrow.triangle.2.circlepath", "Replace Originals with reversible edits")
                        }
                        .padding(18)
                        .slideCropCard(cornerRadius: 20)

                        Text("One-time purchase. No subscription.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        if let message {
                            Text(message)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }

                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await runPurchase()
                                }
                            } label: {
                                Label(unlockButtonTitle, systemImage: "lock.open.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(SlideCropTheme.primaryButtonGradient)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                    )
                                    .shadow(color: SlideCropTheme.indigo.opacity(0.24), radius: 14, y: 8)
                            }
                            .buttonStyle(PressScaleButtonStyle())
                            .disabled(isWorking)

                            Button {
                                Task {
                                    await runRestore()
                                }
                            } label: {
                                Text("Restore Purchases")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(SlideCropTheme.tint)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.62), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PressScaleButtonStyle())
                            .disabled(isWorking)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 26)
                }

                if isWorking {
                    ZStack {
                        Color.black.opacity(0.14).ignoresSafeArea()
                        ProgressView("Please wait")
                            .padding(18)
                            .slideCropCard(cornerRadius: 16)
                    }
                }
            }
            .navigationTitle("SlideCrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                heroVisible = true
            }
        }
    }

    private var paywallMessage: String {
        if remainingFreeSaves <= 0 {
            if let product = purchaseManager.product {
                return "You've used 10 free saves. Unlock unlimited saves for \(product.displayPrice)."
            }
            return "You've used 10 free saves. Unlock unlimited saves."
        }

        return "You have \(remainingFreeSaves) free saves left. Unlock unlimited to save all \(requestedCount) selected images."
    }

    private var unlockButtonTitle: String {
        if let product = purchaseManager.product {
            return "Unlock for \(product.displayPrice)"
        }
        return "Unlock"
    }

    @ViewBuilder
    private func featureRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SlideCropTheme.tint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func runPurchase() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await purchaseManager.purchase()
            dismiss()
        } catch {
            if let purchaseError = error as? PurchaseError, purchaseError == .userCancelled {
                return
            }
            message = error.localizedDescription
        }
    }

    private func runRestore() async {
        isWorking = true
        defer { isWorking = false }

        await purchaseManager.restore()
        if purchaseManager.isUnlocked {
            dismiss()
        } else {
            message = "No previous purchase was found for this Apple ID."
        }
    }
}
