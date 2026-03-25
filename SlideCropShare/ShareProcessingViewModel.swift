import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareProcessingViewModel: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var processedCount = 0
    @Published private(set) var totalCount = 0
    @Published var processedItems: [ProcessedItem] = []
    @Published private(set) var isSaving = false
    @Published var toastMessage: String?

    private let cropService = SlideCropService()
    private let photoLibraryService = PhotoLibraryService()

    func startProcessing(providers: [NSItemProvider]) async {
        guard !providers.isEmpty else { return }

        isProcessing = true
        totalCount = providers.count
        processedCount = 0
        processedItems.removeAll()

        let settings = ProcessingSettings(enhanceReadability: true, quality: .fast)

        for provider in providers {
            guard let imageData = await loadImageData(from: provider) else {
                processedCount += 1
                processedItems.append(ProcessedItem(
                    assetIdentifier: "share-\(UUID().uuidString)",
                    originalThumbnail: nil,
                    processedThumbnail: nil,
                    sourceImageURL: nil,
                    processedImageURL: nil,
                    confidenceScore: 0,
                    status: .failed,
                    cropQuad: nil,
                    errorMessage: "Could not load image data.",
                    canReplaceOriginal: false,
                    canManualAdjust: false
                ))
                continue
            }

            let identifier = "share-\(UUID().uuidString)"
            let result = await cropService.processImageData(
                imageData,
                sourceIdentifier: identifier,
                settings: settings,
                fallbackThumbnail: downsampledImage(from: imageData, maxPixelSize: 380)
            )

            processedItems.append(result)
            processedCount += 1
        }

        isProcessing = false
    }

    func saveAll() async -> Int {
        guard !isSaving else { return 0 }
        isSaving = true
        defer { isSaving = false }

        let saveable = processedItems.filter { $0.processedImageURL != nil && $0.status != .failed }
        guard !saveable.isEmpty else {
            toastMessage = "No items to save."
            return 0
        }

        do {
            try await photoLibraryService.saveNewImages(items: saveable)
            toastMessage = "Saved \(saveable.count) image\(saveable.count == 1 ? "" : "s")."
            return saveable.count
        } catch {
            toastMessage = "Save failed: \(error.localizedDescription)"
            return 0
        }
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
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
}
