import Foundation
import Photos
import UIKit

final class PhotoLibraryService {
    func requestReadWriteAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func canAccessAsset(with localIdentifier: String) -> Bool {
        fetchAsset(with: localIdentifier) != nil
    }

    func requestThumbnail(for localIdentifier: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = fetchAsset(with: localIdentifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var didResume = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else { return }
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
                if isCancelled {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }
                if isDegraded {
                    return
                }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    func requestDisplayImage(for localIdentifier: String, maxPixelSize: CGFloat) async -> UIImage? {
        guard let asset = fetchAsset(with: localIdentifier) else { return nil }

        let longEdge = CGFloat(max(asset.pixelWidth, asset.pixelHeight))
        let scale = maxPixelSize / max(longEdge, 1)
        let size = CGSize(
            width: CGFloat(asset.pixelWidth) * min(scale, 1),
            height: CGFloat(asset.pixelHeight) * min(scale, 1)
        )

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            var didResume = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !didResume else { return }
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
                if isCancelled {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }
                if isDegraded {
                    return
                }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    func saveNewImages(items: [ProcessedItem]) async throws {
        let status = await requestReadWriteAccess()
        guard status == .authorized || status == .limited else {
            throw SlideCropError.permissionDenied
        }

        let urls = items.compactMap(\.processedImageURL)
        guard !urls.isEmpty else { return }

        try await performChanges {
            for url in urls {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            }
        }
    }

    func replaceOriginalImages(items: [ProcessedItem]) async throws -> Int {
        let status = await requestReadWriteAccess()
        guard status == .authorized || status == .limited else {
            throw SlideCropError.permissionDenied
        }

        let editableItems = items.filter { $0.processedImageURL != nil }
        guard !editableItems.isEmpty else { return 0 }

        var replacedCount = 0

        for item in editableItems {
            guard let asset = fetchAsset(with: item.assetIdentifier), let processedURL = item.processedImageURL else {
                continue
            }

            let input = try await requestContentEditingInput(for: asset)
            let output = PHContentEditingOutput(contentEditingInput: input)

            let data = try Data(contentsOf: processedURL)
            try data.write(to: output.renderedContentURL, options: .atomic)

            output.adjustmentData = PHAdjustmentData(
                formatIdentifier: "com.local.SlideCrop.adjustment",
                formatVersion: "1.0",
                data: Data("SlideCropPerspective".utf8)
            )

            try await performChanges {
                let changeRequest = PHAssetChangeRequest(for: asset)
                changeRequest.contentEditingOutput = output
            }
            replacedCount += 1
        }

        return replacedCount
    }

    @MainActor
    func presentLimitedLibraryPicker(from presenter: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    }

    private func fetchAsset(with localIdentifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return fetchResult.firstObject
    }

    private func requestContentEditingInput(for asset: PHAsset) async throws -> PHContentEditingInput {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true

            asset.requestContentEditingInput(with: options) { input, info in
                if let cancelled = info[PHContentEditingInputCancelledKey] as? Bool, cancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if let error = info[PHContentEditingInputErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let input else {
                    continuation.resume(throwing: SlideCropError.outputFailed)
                    return
                }

                continuation.resume(returning: input)
            }
        }
    }

    private func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SlideCropError.outputFailed)
                }
            }
        }
    }
}
