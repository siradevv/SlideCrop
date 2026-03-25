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

    func moveItem(from source: IndexSet, to destination: Int) {
        processedItems.move(fromOffsets: source, toOffset: destination)
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
            let cropService = self.cropService
            let photoLibraryService = self.photoLibraryService
            let indexedInputs = Array(selectedPhotos.enumerated())
            let concurrency = Self.recommendedConcurrency(
                for: settings.quality,
                totalCount: indexedInputs.count
            )

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
                "batch_start run=\(runID.uuidString.prefix(8)) total=\(selectedPhotos.count) quality=\(settings.quality.rawValue) concurrency=\(concurrency)"
            )
            #endif

            var nextToCommitIndex = 0
            var completedBuffer: [Int: IndexedProcessingResult] = [:]
            var nextToScheduleIndex = 0

            await withTaskGroup(of: IndexedProcessingResult.self) { group in
                let initialCount = min(concurrency, indexedInputs.count)
                for _ in 0..<initialCount {
                    let indexed = indexedInputs[nextToScheduleIndex]
                    nextToScheduleIndex += 1
                    group.addTask {
                        await Self.processInput(
                            index: indexed.offset,
                            item: indexed.element,
                            settings: settings,
                            cropService: cropService,
                            photoLibraryService: photoLibraryService
                        )
                    }
                }

                while let completed = await group.next() {
                    if Task.isCancelled || self.currentRunID != runID {
                        group.cancelAll()
                        break
                    }

                    self.processedCount += 1
                    self.currentAssetIdentifier = completed.displayIdentifier
                    self.currentThumbnail = completed.previewThumbnail
                    completedBuffer[completed.index] = completed

                    while let ready = completedBuffer.removeValue(forKey: nextToCommitIndex) {
                        self.processedItems.append(ready.item)
                        nextToCommitIndex += 1
                    }

                    #if DEBUG
                    debugItemTimeMsSum += completed.totalMs
                    registerStatus(completed.item.status)
                    var message = "item \(self.processedCount)/\(selectedPhotos.count) src=\(completed.sourceLabel) status=\(completed.item.status.rawValue) total=\(Self.debugFormatMilliseconds(completed.totalMs))ms"
                    if let loadMs = completed.loadMs {
                        message += " load=\(Self.debugFormatMilliseconds(loadMs))ms"
                    }
                    if let thumbnailMs = completed.thumbnailMs {
                        message += " thumb=\(Self.debugFormatMilliseconds(thumbnailMs))ms"
                    }
                    if let processMs = completed.processMs {
                        message += " process=\(Self.debugFormatMilliseconds(processMs))ms"
                    }
                    if let note = completed.note {
                        message += " reason=\(note)"
                    }
                    self.debugLog(message)
                    #endif

                    if nextToScheduleIndex < indexedInputs.count {
                        let indexed = indexedInputs[nextToScheduleIndex]
                        nextToScheduleIndex += 1
                        group.addTask {
                            await Self.processInput(
                                index: indexed.offset,
                                item: indexed.element,
                                settings: settings,
                                cropService: cropService,
                                photoLibraryService: photoLibraryService
                            )
                        }
                    }
                }
            }

            guard self.currentRunID == runID else { return }
            self.isProcessing = false
            self.processingTask = nil

            #if DEBUG
            let debugBatchMs = Self.elapsedMilliseconds(since: debugBatchStart)
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

    private static func elapsedMilliseconds(since startUptime: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - startUptime) * 1000.0
    }

    private static func recommendedConcurrency(
        for quality: ProcessingQuality,
        totalCount: Int
    ) -> Int {
        guard totalCount > 0 else { return 1 }
        let qualityCap = quality == .fast ? 3 : 2
        let cpuCap = max(1, min(3, ProcessInfo.processInfo.activeProcessorCount))
        let target = min(qualityCap, cpuCap)
        return max(1, min(totalCount, target))
    }

    private static func processInput(
        index: Int,
        item: SelectedPhotoInput,
        settings: ProcessingSettings,
        cropService: SlideCropService,
        photoLibraryService: PhotoLibraryService
    ) async -> IndexedProcessingResult {
        let itemStart = ProcessInfo.processInfo.systemUptime

        if let identifier = item.assetIdentifier {
            let thumbStart = ProcessInfo.processInfo.systemUptime
            let thumbnail = await photoLibraryService.requestThumbnail(
                for: identifier,
                targetSize: CGSize(width: 380, height: 380)
            )
            let thumbMs = elapsedMilliseconds(since: thumbStart)

            let processStart = ProcessInfo.processInfo.systemUptime
            let result = await cropService.processAsset(
                assetIdentifier: identifier,
                settings: settings,
                fallbackThumbnail: thumbnail
            )
            let processMs = elapsedMilliseconds(since: processStart)

            return IndexedProcessingResult(
                index: index,
                displayIdentifier: identifier,
                previewThumbnail: thumbnail,
                item: result,
                sourceLabel: "asset",
                loadMs: nil,
                thumbnailMs: thumbMs,
                processMs: processMs,
                totalMs: elapsedMilliseconds(since: itemStart),
                note: nil
            )
        }

        if let imageData = item.imageData {
            let syntheticIdentifier = "camera-\(UUID().uuidString)"

            let thumbStart = ProcessInfo.processInfo.systemUptime
            let fallbackThumbnail = downsampledImage(from: imageData, maxPixelSize: 460)
            let thumbMs = elapsedMilliseconds(since: thumbStart)

            let processStart = ProcessInfo.processInfo.systemUptime
            let result = await cropService.processImageData(
                imageData,
                sourceIdentifier: syntheticIdentifier,
                settings: settings,
                fallbackThumbnail: fallbackThumbnail
            )
            let processMs = elapsedMilliseconds(since: processStart)

            return IndexedProcessingResult(
                index: index,
                displayIdentifier: syntheticIdentifier,
                previewThumbnail: fallbackThumbnail,
                item: result,
                sourceLabel: "camera",
                loadMs: 0,
                thumbnailMs: thumbMs,
                processMs: processMs,
                totalMs: elapsedMilliseconds(since: itemStart),
                note: nil
            )
        }

        let syntheticIdentifier = "picker-\(UUID().uuidString)"
        guard let provider = item.itemProvider else {
            return IndexedProcessingResult(
                index: index,
                displayIdentifier: syntheticIdentifier,
                previewThumbnail: nil,
                item: makeImportFailureItem(assetIdentifier: syntheticIdentifier, reason: "No image provider available for this selection."),
                sourceLabel: "itemProvider",
                loadMs: nil,
                thumbnailMs: nil,
                processMs: nil,
                totalMs: elapsedMilliseconds(since: itemStart),
                note: "missing_provider"
            )
        }

        let loadStart = ProcessInfo.processInfo.systemUptime
        guard let imageData = await loadImageData(from: provider) else {
            return IndexedProcessingResult(
                index: index,
                displayIdentifier: syntheticIdentifier,
                previewThumbnail: nil,
                item: makeImportFailureItem(assetIdentifier: syntheticIdentifier, reason: "Could not load image data. The file may be in an unsupported format."),
                sourceLabel: "itemProvider",
                loadMs: elapsedMilliseconds(since: loadStart),
                thumbnailMs: nil,
                processMs: nil,
                totalMs: elapsedMilliseconds(since: itemStart),
                note: "load_failed"
            )
        }
        let loadMs = elapsedMilliseconds(since: loadStart)

        let thumbStart = ProcessInfo.processInfo.systemUptime
        let fallbackThumbnail = downsampledImage(from: imageData, maxPixelSize: 460)
        let thumbMs = elapsedMilliseconds(since: thumbStart)

        let processStart = ProcessInfo.processInfo.systemUptime
        let result = await cropService.processImageData(
            imageData,
            sourceIdentifier: syntheticIdentifier,
            settings: settings,
            fallbackThumbnail: fallbackThumbnail
        )
        let processMs = elapsedMilliseconds(since: processStart)

        return IndexedProcessingResult(
            index: index,
            displayIdentifier: syntheticIdentifier,
            previewThumbnail: fallbackThumbnail,
            item: result,
            sourceLabel: "itemProvider",
            loadMs: loadMs,
            thumbnailMs: thumbMs,
            processMs: processMs,
            totalMs: elapsedMilliseconds(since: itemStart),
            note: nil
        )
    }

    private static func makeImportFailureItem(assetIdentifier: String, reason: String = "Unable to import this selected photo.") -> ProcessedItem {
        ProcessedItem(
            assetIdentifier: assetIdentifier,
            originalThumbnail: nil,
            processedThumbnail: nil,
            sourceImageURL: nil,
            processedImageURL: nil,
            confidenceScore: 0,
            status: .failed,
            cropQuad: nil,
            errorMessage: reason,
            canReplaceOriginal: false,
            canManualAdjust: false
        )
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

    private struct IndexedProcessingResult {
        let index: Int
        let displayIdentifier: String
        let previewThumbnail: UIImage?
        let item: ProcessedItem
        let sourceLabel: String
        let loadMs: Double?
        let thumbnailMs: Double?
        let processMs: Double?
        let totalMs: Double
        let note: String?
    }

    private func cleanupTemporaryFiles(in items: [ProcessedItem]) {
        let urls = Set(items.compactMap(\.processedImageURL) + items.compactMap(\.sourceImageURL))
        guard !urls.isEmpty else { return }

        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    #if DEBUG
    private static func debugFormatMilliseconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func debugLog(_ message: String) {
        print("[SlideCrop][Processing] \(message)")
    }
    #endif
}
