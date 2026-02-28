import SwiftUI

struct ProcessingView: View {
    @ObservedObject var viewModel: ProcessingViewModel
    let onFinished: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            VStack(spacing: 18) {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .tint(SlideCropTheme.tint)
                    .frame(maxWidth: 320)

                Text("Processing \(viewModel.progressText)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let preview = viewModel.currentThumbnail {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 224, height: 224)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.easeOut(duration: 0.2), value: preview)
                }

                if viewModel.isProcessing {
                    Button("Cancel") {
                        viewModel.cancel()
                        onCancel()
                    }
                    .font(.headline)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.secondary)
                } else {
                    Button("View Results") {
                        onFinished()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(SlideCropTheme.primaryButtonGradient))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .slideCropCard(cornerRadius: 28)
            .padding(.horizontal, 12)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(SlideCropPageBackground())
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .interactiveDismissDisabled(viewModel.isProcessing)
    }

    private var progressValue: Double {
        guard viewModel.totalCount > 0 else { return 0 }
        return Double(viewModel.processedCount) / Double(viewModel.totalCount)
    }
}
