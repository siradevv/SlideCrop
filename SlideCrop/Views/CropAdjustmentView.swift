import AVFoundation
import ImageIO
import SwiftUI

struct CropAdjustmentView: View {
    let assetIdentifier: String
    let sourceImageURL: URL?
    let initialQuad: CropQuad
    let settings: ProcessingSettings
    let originalThumbnail: UIImage?
    let canReplaceOriginal: Bool
    let canManualAdjust: Bool
    let onApply: (ProcessedItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayImage: UIImage?
    @State private var quad: CropQuad
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var zoomScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var quadHistory: [CropQuad] = []
    @State private var pendingHistorySnapshot: CropQuad?

    private let photoLibraryService = PhotoLibraryService()
    private let cropService = SlideCropService()

    init(
        assetIdentifier: String,
        sourceImageURL: URL?,
        initialQuad: CropQuad,
        settings: ProcessingSettings,
        originalThumbnail: UIImage?,
        canReplaceOriginal: Bool,
        canManualAdjust: Bool,
        onApply: @escaping (ProcessedItem) -> Void
    ) {
        self.assetIdentifier = assetIdentifier
        self.sourceImageURL = sourceImageURL
        self.initialQuad = initialQuad
        self.settings = settings
        self.originalThumbnail = originalThumbnail
        self.canReplaceOriginal = canReplaceOriginal
        self.canManualAdjust = canManualAdjust
        self.onApply = onApply
        _quad = State(initialValue: initialQuad)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.08),
                        Color(red: 0.08, green: 0.07, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [SlideCropTheme.rose.opacity(0.20), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [SlideCropTheme.indigo.opacity(0.22), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()

                if let image = displayImage {
                    GeometryReader { proxy in
                        let container = CGRect(origin: .zero, size: proxy.size)
                        let fitted = AVMakeRect(aspectRatio: image.size, insideRect: container)
                        let effectiveZoom = max(1, min(6, zoomScale * pinchScale))
                        let canvasSize = CGSize(
                            width: fitted.width * effectiveZoom,
                            height: fitted.height * effectiveZoom
                        )
                        let contentSize = CGSize(
                            width: max(proxy.size.width, canvasSize.width),
                            height: max(proxy.size.height, canvasSize.height)
                        )

                        ScrollView([.horizontal, .vertical], showsIndicators: false) {
                            ZStack {
                                Color.clear
                                    .frame(width: contentSize.width, height: contentSize.height)

                                ZStack {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: canvasSize.width, height: canvasSize.height)

                                    CropOverlayView(
                                        quad: $quad,
                                        image: image,
                                        onInteractionBegan: beginQuadInteraction,
                                        onInteractionEnded: commitQuadInteraction
                                    )
                                    .frame(width: canvasSize.width, height: canvasSize.height)
                                }
                            }
                        }
                        .gesture(
                            MagnificationGesture()
                                .updating($pinchScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    zoomScale = max(1, min(6, zoomScale * value))
                                }
                        )
                        .overlay(alignment: .bottom) {
                            zoomControls(effectiveZoom: effectiveZoom)
                        }
                    }
                } else {
                    ProgressView("Loading image")
                        .tint(SlideCropTheme.cropAccent)
                }

                if isApplying {
                    ProgressView("Applying crop")
                        .tint(SlideCropTheme.cropAccent)
                        .padding(14)
                        .slideCropCard(cornerRadius: 12)
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        Task {
                            await applyCrop()
                        }
                    }
                    .font(.headline)
                    .disabled(displayImage == nil || isApplying)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background {
                        if displayImage == nil || isApplying {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                        } else {
                            Capsule()
                                .fill(SlideCropTheme.primaryButtonGradient)
                        }
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        undoLastAdjustment()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.95))
                    .background(Color.white.opacity(0.10), in: Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .disabled(quadHistory.isEmpty)
                }
            }
            .task {
                displayImage = await loadEditorImage()
            }
            .alert(
                "Crop Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func applyCrop() async {
        guard !isApplying else { return }
        isApplying = true

        do {
            let updated = try await cropService.processManualAdjustment(
                assetIdentifier: assetIdentifier,
                sourceImageURL: sourceImageURL,
                quad: quad.clamped(),
                settings: settings,
                originalThumbnail: originalThumbnail,
                canReplaceOriginal: canReplaceOriginal,
                canManualAdjust: canManualAdjust
            )
            onApply(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    private func loadEditorImage() async -> UIImage? {
        if let assetImage = await photoLibraryService.requestDisplayImage(
            for: assetIdentifier,
            maxPixelSize: 2600
        ) {
            return assetImage
        }

        guard let sourceImageURL, let data = try? Data(contentsOf: sourceImageURL) else {
            return originalThumbnail
        }

        return downsampledImage(from: data, maxPixelSize: 2600) ?? UIImage(data: data) ?? originalThumbnail
    }

    private func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    @ViewBuilder
    private func zoomControls(effectiveZoom: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button {
                zoomScale = max(1, zoomScale - 0.35)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("\(Int(effectiveZoom * 100))%")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 56)

            Button {
                zoomScale = min(6, zoomScale + 0.35)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        .padding(.bottom, 16)
    }

    private func beginQuadInteraction() {
        guard pendingHistorySnapshot == nil else { return }
        pendingHistorySnapshot = quad
    }

    private func commitQuadInteraction() {
        guard let snapshot = pendingHistorySnapshot else { return }
        pendingHistorySnapshot = nil

        guard snapshot != quad else { return }
        quadHistory.append(snapshot)

        if quadHistory.count > 40 {
            quadHistory.removeFirst(quadHistory.count - 40)
        }
    }

    private func undoLastAdjustment() {
        guard let previous = quadHistory.popLast() else { return }
        pendingHistorySnapshot = nil
        quad = previous
    }
}
