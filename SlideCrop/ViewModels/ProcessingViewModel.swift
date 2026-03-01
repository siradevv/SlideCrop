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

            #if DEBUG
            let debugBatchStart = ProcessInfo.processInfo.systemUptime
            var debugItemTimeMsSum = 0.0
            var debugReadyCount = 0
            var debugReviewCount = 0
            var debugFailedCount = 0

            func registerStatus(_ status: ProcessedStatus) {
                switch status {
                case .auto:
                    debugReadyCount += 1
                case .review:
                    debugReviewCount += 1
                case .failed:
                    debugFailedCount += 1
                }
            }

            self.debugLog(
                "batch_start run=\(runID.uuidString.prefix(8)) total=\(selectedPhotos.count) quality=\(settings.quality.rawValue) concurrency=1"
            )
            #endif

            for item in selectedPhotos {
                if Task.isCancelled { break }
                if self.currentRunID != runID { break }

                if let identifier = item.assetIdentifier {
                    #if DEBUG
                    let debugItemStart = ProcessInfo.processInfo.systemUptime
                    let debugThumbStart = ProcessInfo.processInfo.systemUptime
                    #endif

                    self.currentAssetIdentifier = identifier
                    self.currentThumbnail = await self.photoLibraryService.requestThumbnail(
                        for: identifier,
                        targetSize: CGSize(width: 380, height: 380)
                    )

                    #if DEBUG
                    let debugThumbMs = Self.debugElapsedMilliseconds(since: debugThumbStart)
                    let debugProcessStart = ProcessInfo.processInfo.systemUptime
                    #endif

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

                    #if DEBUG
                    let debugProcessMs = Self.debugElapsedMilliseconds(since: debugProcessStart)
                    let debugItemMs = Self.debugElapsedMilliseconds(since: debugItemStart)
                    debugItemTimeMsSum += debugItemMs
                    registerStatus(result.status)
                    self.debugLog(
                        "item \(self.processedCount)/\(selectedPhotos.count) src=asset status=\(result.status.rawValue) total=\(Self.debugFormatMilliseconds(debugItemMs))ms thumb=\(Self.debugFormatMilliseconds(debugThumbMs))ms process=\(Self.debugFormatMilliseconds(debugProcessMs))ms"
                    )
                    #endif
                    continue
                }

                #if DEBUG
                let debugItemStart = ProcessInfo.processInfo.systemUptime
                #endif

                let syntheticIdentifier = "picker-\(UUID().uuidString)"
                self.currentAssetIdentifier = syntheticIdentifier

                guard let provider = item.itemProvider else {
                    let failedItem = ProcessedItem(
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
                    self.processedItems.append(failedItem)
                    self.processedCount += 1

                    #if DEBUG
                    let debugItemMs = Self.debugElapsedMilliseconds(since: debugItemStart)
                    debugItemTimeMsSum += debugItemMs
                    registerStatus(failedItem.status)
                    self.debugLog(
                        "item \(self.processedCount)/\(selectedPhotos.count) src=itemProvider status=\(failedItem.status.rawValue) total=\(Self.debugFormatMilliseconds(debugItemMs))ms reason=missing_provider"
                    )
                    #endif
                    continue
                }

                #if DEBUG
                let debugLoadStart = ProcessInfo.processInfo.systemUptime
                #endif
                let imageData = await Self.loadImageData(from: provider)
                #if DEBUG
                let debugLoadMs = Self.debugElapsedMilliseconds(since: debugLoadStart)
                #endif
                if Task.isCancelled { break }
                if self.currentRunID != runID { break }

                guard let imageData else {
                    let failedItem = ProcessedItem(
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
                    self.processedItems.append(failedItem)
                    self.processedCount += 1

                    #if DEBUG
                    let debugItemMs = Self.debugElapsedMilliseconds(since: debugItemStart)
                    debugItemTimeMsSum += debugItemMs
                    registerStatus(failedItem.status)
                    self.debugLog(
                        "item \(self.processedCount)/\(selectedPhotos.count) src=itemProvider status=\(failedItem.status.rawValue) total=\(Self.debugFormatMilliseconds(debugItemMs))ms load=\(Self.debugFormatMilliseconds(debugLoadMs))ms reason=load_failed"
                    )
                    #endif
                    continue
                }

                #if DEBUG
                let debugThumbStart = ProcessInfo.processInfo.systemUptime
                #endif
                let fallbackThumbnail = Self.downsampledImage(
                    from: imageData,
                    maxPixelSize: 460
                )
                #if DEBUG
                let debugThumbMs = Self.debugElapsedMilliseconds(since: debugThumbStart)
                let debugProcessStart = ProcessInfo.processInfo.systemUptime
                #endif
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

                #if DEBUG
                let debugProcessMs = Self.debugElapsedMilliseconds(since: debugProcessStart)
                let debugItemMs = Self.debugElapsedMilliseconds(since: debugItemStart)
                debugItemTimeMsSum += debugItemMs
                registerStatus(result.status)
                self.debugLog(
                    "item \(self.processedCount)/\(selectedPhotos.count) src=itemProvider status=\(result.status.rawValue) total=\(Self.debugFormatMilliseconds(debugItemMs))ms load=\(Self.debugFormatMilliseconds(debugLoadMs))ms thumb=\(Self.debugFormatMilliseconds(debugThumbMs))ms process=\(Self.debugFormatMilliseconds(debugProcessMs))ms"
                )
                #endif
            }

            guard self.currentRunID == runID else { return }
            self.isProcessing = false
            self.processingTask = nil

            #if DEBUG
            let debugBatchMs = Self.debugElapsedMilliseconds(since: debugBatchStart)
            let processed = self.processedCount
            let avgWallPerImage = processed > 0 ? debugBatchMs / Double(processed) : 0
            let avgTrackedItemMs = processed > 0 ? debugItemTimeMsSum / Double(processed) : 0
            let imagesPerSecond = debugBatchMs > 0 ? (Double(processed) / (debugBatchMs / 1000.0)) : 0
            self.debugLog(
                "batch_end run=\(runID.uuidString.prefix(8)) processed=\(processed)/\(selectedPhotos.count) ready=\(debugReadyCount) review=\(debugReviewCount) failed=\(debugFailedCount) total=\(Self.debugFormatMilliseconds(debugBatchMs))ms avgWall=\(Self.debugFormatMilliseconds(avgWallPerImage))ms avgItem=\(Self.debugFormatMilliseconds(avgTrackedItemMs))ms ips=\(String(format: "%.2f", imagesPerSecond)) cancelled=\(Task.isCancelled)"
            )
            #endif
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

    #if DEBUG
    private static func debugElapsedMilliseconds(since startUptime: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - startUptime) * 1000.0
    }

    private static func debugFormatMilliseconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func debugLog(_ message: String) {
        print("[SlideCrop][Processing] \(message)")
    }
    #endif
}
