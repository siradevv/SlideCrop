import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var processedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var currentThumbnail: UIImage?
    @Published private(set) var currentAssetIdentifier: String?
    @Published var processedItems: [ProcessedItem] = []

    private let cropService: SlideCropService
    private let photoLibraryService: PhotoLibraryService
    private var processingTask: Task<Void, Never>?
    private var currentRunID = UUID()

    init(
        cropService: SlideCropService = SlideCropService(),
        photoLibraryService: PhotoLibraryService = PhotoLibraryService()
    ) {
        self.cropService = cropService
        self.photoLibraryService = photoLibraryService
    }

    var hasCompletedRun: Bool {
        !isProcessing && totalCount > 0
    }

    var progressText: String {
        "\(min(processedCount, totalCount)) of \(totalCount)"
    }

    func startProcessing(selectedPhotos: [SelectedPhotoInput], settings: ProcessingSettings) {
        cancel()

        guard !selectedPhotos.isEmpty else { return }

        processedItems.removeAll(keepingCapacity: true)
        processedCount = 0
        totalCount = selectedPhotos.count
        currentThumbnail = nil
        currentAssetIdentifier = nil
        isProcessing = true
        let runID = UUID()
        currentRunID = runID

        processingTask = Task { [weak self] in
            guard let self else { return }

            for item in selectedPhotos {
                if Task.isCancelled { break }
                if self.currentRunID != runID { break }

                if let identifier = item.assetIdentifier {
                    self.currentAssetIdentifier = identifier
                    self.currentThumbnail = await self.photoLibraryService.requestThumbnail(
                        for: identifier,
                        targetSize: CGSize(width: 380, height: 380)
                    )
                    if Task.isCancelled { break }
                    if self.currentRunID != runID { break }

                    let result = await self.cropService.processAsset(
                        assetIdentifier: identifier,
                        settings: settings,
                        fallbackThumbnail: self.currentThumbnail
                    )
                    if Task.isCancelled { break }
                    if self.currentRunID != runID { break }
                    self.processedItems.append(result)
                    self.processedCount += 1
                    continue
                }

                let syntheticIdentifier = "picker-\(UUID().uuidString)"
                self.currentAssetIdentifier = syntheticIdentifier

                guard let provider = item.itemProvider else {
                    self.processedItems.append(
                        ProcessedItem(
                            assetIdentifier: syntheticIdentifier,
                            originalThumbnail: nil,
                            processedThumbnail: nil,
                            sourceImageURL: nil,
                            processedImageURL: nil,
                            confidenceScore: 0,
                            status: .failed,
                            cropQuad: nil,
                            errorMessage: "Unable to import this selected photo.",
                            canReplaceOriginal: false,
                            canManualAdjust: false
                        )
                    )
                    self.processedCount += 1
                    continue
                }

                let imageData = await Self.loadImageData(from: provider)
                if Task.isCancelled { break }
                if self.currentRunID != runID { break }

                guard let imageData else {
                    self.processedItems.append(
                        ProcessedItem(
                            assetIdentifier: syntheticIdentifier,
                            originalThumbnail: nil,
                            processedThumbnail: nil,
                            sourceImageURL: nil,
                            processedImageURL: nil,
                            confidenceScore: 0,
                            status: .failed,
                            cropQuad: nil,
                            errorMessage: "Unable to import this selected photo.",
                            canReplaceOriginal: false,
                            canManualAdjust: false
                        )
                    )
                    self.processedCount += 1
                    continue
                }

                let fallbackThumbnail = Self.downsampledImage(
                    from: imageData,
                    maxPixelSize: 460
                )
                self.currentThumbnail = fallbackThumbnail
                if Task.isCancelled { break }
                if self.currentRunID != runID { break }

                let result = await self.cropService.processImageData(
                    imageData,
                    sourceIdentifier: syntheticIdentifier,
                    settings: settings,
                    fallbackThumbnail: fallbackThumbnail
                )
                if Task.isCancelled { break }
                if self.currentRunID != runID { break }

                self.processedItems.append(result)
                self.processedCount += 1
            }

            guard self.currentRunID == runID else { return }
            self.isProcessing = false
            self.processingTask = nil
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        currentRunID = UUID()

        cleanupTemporaryFiles(in: processedItems)
        processedItems.removeAll(keepingCapacity: true)

        isProcessing = false
        processedCount = 0
        totalCount = 0
        currentThumbnail = nil
        currentAssetIdentifier = nil
    }

    private static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func cleanupTemporaryFiles(in items: [ProcessedItem]) {
        let urls = Set(items.compactMap(\.processedImageURL) + items.compactMap(\.sourceImageURL))
        guard !urls.isEmpty else { return }

        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
