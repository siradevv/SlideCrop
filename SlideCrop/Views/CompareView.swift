import SwiftUI

struct CompareView: View {
    @Binding var item: ProcessedItem
    let settings: ProcessingSettings
    var onManualAdjustmentApplied: ((ProcessedItem) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var isLoading = false
    @State private var showAdjustment = false

    private let photoLibraryService = PhotoLibraryService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if isLoading {
                    ProgressView("Loading comparison")
                        .tint(SlideCropTheme.tint)
                        .frame(maxHeight: .infinity)
                } else {
                    GeometryReader { proxy in
                        let paneHeight = max((proxy.size.height - 12) / 2, 220)

                        VStack(spacing: 12) {
                            imagePane(title: "Before", image: beforeImage ?? item.originalThumbnail)
                                .frame(height: paneHeight)

                            imagePane(title: "After", image: afterImage ?? item.processedThumbnail)
                                .frame(height: paneHeight)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 14)

                    HStack(spacing: 10) {
                        Button("Adjust Crop") {
                            showAdjustment = true
                        }
                        .buttonStyle(.bordered)
                        .tint(SlideCropTheme.tint.opacity(0.9))
                        .disabled(!item.canManualAdjust)

                        Button("Use This") {
                            if item.status == .review, item.processedImageURL != nil {
                                item.status = .auto
                                item.errorMessage = nil
                            }
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SlideCropTheme.tint)
                    }
                    .padding(.bottom, 14)
                }
            }
            .background(SlideCropPageBackground())
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                await loadImages()
            }
            .sheet(isPresented: $showAdjustment) {
                CropAdjustmentView(
                    assetIdentifier: item.assetIdentifier,
                    sourceImageURL: item.sourceImageURL,
                    initialQuad: item.cropQuad ?? .full,
                    settings: settings,
                    originalThumbnail: item.originalThumbnail,
                    canReplaceOriginal: item.canReplaceOriginal,
                    canManualAdjust: item.canManualAdjust
                ) { updated in
                    var merged = updated
                    merged.id = item.id
                    item = merged
                    afterImage = merged.processedThumbnail ?? merged.processedImageURL.flatMap { UIImage(contentsOfFile: $0.path) }
                    onManualAdjustmentApplied?(merged)
                }
            }
        }
    }

    @ViewBuilder
    private func imagePane(title: String, image: UIImage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if let image {
                    ZoomableImageView(image: image)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Image unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SlideCropTheme.imagePaneBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SlideCropTheme.imagePaneStroke, lineWidth: 1)
            )
            .shadow(color: SlideCropTheme.panelShadow, radius: 10, y: 5)
        }
    }

    private func loadImages() async {
        isLoading = true

        async let before = photoLibraryService.requestDisplayImage(
            for: item.assetIdentifier,
            maxPixelSize: 2400
        )

        let processed = item.processedImageURL.flatMap { UIImage(contentsOfFile: $0.path) }

        beforeImage = await before ?? item.originalThumbnail
        afterImage = processed ?? item.processedThumbnail

        isLoading = false
    }
}
