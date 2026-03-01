import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Photos
import QuartzCore
import UIKit
import UniformTypeIdentifiers
import Vision

final class SlideCropService {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func processAsset(
        assetIdentifier: String,
        settings: ProcessingSettings,
        fallbackThumbnail: UIImage?
    ) async -> ProcessedItem {
        guard let asset = fetchAsset(with: assetIdentifier) else {
            return ProcessedItem(
                assetIdentifier: assetIdentifier,
                originalThumbnail: fallbackThumbnail,
                processedThumbnail: nil,
                sourceImageURL: nil,
                processedImageURL: nil,
                confidenceScore: 0,
                status: .failed,
                cropQuad: nil,
                errorMessage: SlideCropError.assetNotFound.localizedDescription,
                canReplaceOriginal: false,
                canManualAdjust: false
            )
        }

        do {
            let fullImage = try await loadHighResolutionCIImage(for: asset)
            return try await runOnProcessingQueue {
                try self.processLoadedImage(
                    fullImage,
                    assetIdentifier: assetIdentifier,
                    settings: settings,
                    fallbackThumbnail: fallbackThumbnail,
                    sourceImageURL: nil,
                    canReplaceOriginal: true,
                    canManualAdjust: true
                )
            }
        } catch {
            return ProcessedItem(
                assetIdentifier: assetIdentifier,
                originalThumbnail: fallbackThumbnail,
                processedThumbnail: nil,
                sourceImageURL: nil,
                processedImageURL: nil,
                confidenceScore: 0,
                status: .failed,
                cropQuad: nil,
                errorMessage: error.localizedDescription,
                canReplaceOriginal: false,
                canManualAdjust: false
            )
        }
    }

    func processImageData(
        _ data: Data,
        sourceIdentifier: String,
        settings: ProcessingSettings,
        fallbackThumbnail: UIImage?
    ) async -> ProcessedItem {
        let sourceImageURL = persistSourceImageData(data)

        guard let fullImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return ProcessedItem(
                assetIdentifier: sourceIdentifier,
                originalThumbnail: fallbackThumbnail,
                processedThumbnail: nil,
                sourceImageURL: sourceImageURL,
                processedImageURL: nil,
                confidenceScore: 0,
                status: .failed,
                cropQuad: nil,
                errorMessage: SlideCropError.imageDataUnavailable.localizedDescription,
                canReplaceOriginal: false,
                canManualAdjust: sourceImageURL != nil
            )
        }

        do {
            let result = try await runOnProcessingQueue {
                try self.processLoadedImage(
                    fullImage,
                    assetIdentifier: sourceIdentifier,
                    settings: settings,
                    fallbackThumbnail: fallbackThumbnail,
                    sourceImageURL: sourceImageURL,
                    canReplaceOriginal: false,
                    canManualAdjust: sourceImageURL != nil
                )
            }
            return result
        } catch {
            return ProcessedItem(
                assetIdentifier: sourceIdentifier,
                originalThumbnail: fallbackThumbnail,
                processedThumbnail: nil,
                sourceImageURL: sourceImageURL,
                processedImageURL: nil,
                confidenceScore: 0,
                status: .failed,
                cropQuad: nil,
                errorMessage: error.localizedDescription,
                canReplaceOriginal: false,
                canManualAdjust: sourceImageURL != nil
            )
        }
    }

    func processManualAdjustment(
        assetIdentifier: String,
        sourceImageURL: URL?,
        quad: CropQuad,
        settings: ProcessingSettings,
        originalThumbnail: UIImage?,
        canReplaceOriginal: Bool,
        canManualAdjust: Bool
    ) async throws -> ProcessedItem {
        let fullImage = try await loadManualSourceImage(
            assetIdentifier: assetIdentifier,
            sourceImageURL: sourceImageURL
        )
        return try await runOnProcessingQueue {
            let cleaned = quad.clamped()
            let perspectiveStart = self.debugTimestamp()
            guard var corrected = self.applyPerspectiveCorrection(to: fullImage, quad: cleaned) else {
                throw SlideCropError.perspectiveFailed
            }
            self.debugLogTiming(step: "perspective", start: perspectiveStart, assetIdentifier: assetIdentifier)

            if settings.enhanceReadability {
                let enhancementStart = self.debugTimestamp()
                corrected = self.applyEnhancementMaximumClean(to: corrected, context: self.ciContext)
                self.debugLogTiming(step: "enhancement", start: enhancementStart, assetIdentifier: assetIdentifier)
            }

            self.debugLogCorrectedExtent(corrected.extent, assetIdentifier: assetIdentifier)
            let exportStart = self.debugTimestamp()
            let outputURL = try self.exportJPEG(image: corrected, quality: 0.9)
            self.debugLogTiming(step: "jpeg-export", start: exportStart, assetIdentifier: assetIdentifier)
            let thumbnail = self.makeThumbnail(from: corrected, maxLongEdge: 520)

            return ProcessedItem(
                assetIdentifier: assetIdentifier,
                originalThumbnail: originalThumbnail,
                processedThumbnail: thumbnail,
                sourceImageURL: sourceImageURL,
                processedImageURL: outputURL,
                confidenceScore: 1,
                status: .auto,
                cropQuad: cleaned,
                errorMessage: nil,
                canReplaceOriginal: canReplaceOriginal,
                canManualAdjust: canManualAdjust
            )
        }
    }

    private func runOnProcessingQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result: T = try autoreleasepool {
                        try work()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func processLoadedImage(
        _ fullImage: CIImage,
        assetIdentifier: String,
        settings: ProcessingSettings,
        fallbackThumbnail: UIImage?,
        sourceImageURL: URL?,
        canReplaceOriginal: Bool,
        canManualAdjust: Bool
    ) throws -> ProcessedItem {
        let detectionImage = resized(image: fullImage, maxLongEdge: settings.quality.detectionLongEdge)
        guard let detectionCGImage = ciContext.createCGImage(detectionImage, from: detectionImage.extent) else {
            throw SlideCropError.imageDataUnavailable
        }

        let observations = try detectRectangles(in: detectionCGImage)
        let quads = observations.map(cropQuad(from:))

        guard !quads.isEmpty else {
            return ProcessedItem(
                assetIdentifier: assetIdentifier,
                originalThumbnail: fallbackThumbnail,
                processedThumbnail: nil,
                sourceImageURL: sourceImageURL,
                processedImageURL: nil,
                confidenceScore: 0,
                status: .failed,
                cropQuad: nil,
                errorMessage: "No slide rectangle detected.",
                canReplaceOriginal: canReplaceOriginal,
                canManualAdjust: canManualAdjust
            )
        }

        let scoredCandidates = quads.compactMap { scoreCandidate($0, in: detectionImage) }
        let sortedCandidates = scoredCandidates.sorted { $0.totalScore > $1.totalScore }
        guard let topCandidate = sortedCandidates.first else {
            throw SlideCropError.perspectiveFailed
        }

        let refinedCandidates = refinementVariants(for: topCandidate.quad)
            .compactMap { scoreCandidate($0, in: detectionImage) }
        guard let best = bestCandidate(in: refinedCandidates) else {
            throw SlideCropError.perspectiveFailed
        }

        let refinementChanged = best.quad != topCandidate.quad
        let secondBestScore = sortedCandidates.count > 1 ? sortedCandidates[1].totalScore : 0
        let gap = best.totalScore - secondBestScore

        let ambiguous = gap < 0.06
        let borderRisk = best.edgeMarginScore < 0.35
        let geometryWeak = best.skewScore < 0.78 || best.aspectScore < 0.55
        let extremeArea = best.areaRatio < 0.18 || best.areaRatio > 0.90

        let defaultAuto =
            best.totalScore >= 0.62 &&
            !ambiguous &&
            !borderRisk &&
            !geometryWeak &&
            !extremeArea

        let goodCropRescue =
            best.totalScore >= 0.56 &&
            best.skewScore >= 0.88 &&
            best.aspectScore >= 0.72 &&
            best.edgeMarginScore >= 0.38 &&
            gap >= 0.04

        let status: ProcessedStatus = (defaultAuto || goodCropRescue) ? .auto : .review
        debugLogDecision(
            assetIdentifier: assetIdentifier,
            best: best,
            gap: gap,
            status: status,
            refinementChanged: refinementChanged
        )

        let perspectiveStart = debugTimestamp()
        guard var corrected = applyPerspectiveCorrection(to: fullImage, quad: best.quad) else {
            throw SlideCropError.perspectiveFailed
        }
        debugLogTiming(step: "perspective", start: perspectiveStart, assetIdentifier: assetIdentifier)

        if settings.enhanceReadability {
            let enhancementStart = debugTimestamp()
            corrected = applyEnhancementMaximumClean(to: corrected, context: ciContext)
            debugLogTiming(step: "enhancement", start: enhancementStart, assetIdentifier: assetIdentifier)
        }

        debugLogCorrectedExtent(corrected.extent, assetIdentifier: assetIdentifier)
        let exportStart = debugTimestamp()
        let outputURL = try exportJPEG(image: corrected, quality: 0.9)
        debugLogTiming(step: "jpeg-export", start: exportStart, assetIdentifier: assetIdentifier)
        let processedThumbnail = makeThumbnail(from: corrected, maxLongEdge: 520)

        return ProcessedItem(
            assetIdentifier: assetIdentifier,
            originalThumbnail: fallbackThumbnail,
            processedThumbnail: processedThumbnail,
            sourceImageURL: sourceImageURL,
            processedImageURL: outputURL,
            confidenceScore: best.totalScore,
            status: status,
            cropQuad: best.quad,
            errorMessage: nil,
            canReplaceOriginal: canReplaceOriginal,
            canManualAdjust: canManualAdjust
        )
    }

    private func detectRectangles(in image: CGImage) throws -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 10
        request.minimumConfidence = 0.5
        request.minimumSize = 0.2
        request.quadratureTolerance = 22

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    private func cropQuad(from observation: VNRectangleObservation) -> CropQuad {
        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: 1 - point.y)
        }

        return CropQuad(
            topLeft: convert(observation.topLeft),
            topRight: convert(observation.topRight),
            bottomRight: convert(observation.bottomRight),
            bottomLeft: convert(observation.bottomLeft)
        ).clamped()
    }

    private func scoreCandidate(_ quad: CropQuad, in image: CIImage) -> CandidateScore? {
        guard let corrected = applyPerspectiveCorrection(to: image, quad: quad) else {
            return nil
        }

        let areaRatio = clamp01(Double(quad.area))
        let areaScore = normalizedAreaScore(for: areaRatio)

        let aspect = Double(corrected.extent.width / max(corrected.extent.height, 1))
        let aspectScore = aspectClosenessScore(aspect)

        let center = quad.centroid
        let centerDistance = hypot(center.x - 0.5, center.y - 0.5)
        let centerednessScore = max(0, 1 - Double(centerDistance / 0.7071))

        let skewScore = skewSanityScore(for: quad)

        let textScore = textDensityBonus(in: corrected)
        let edgeMarginScore = edgeMarginScore(for: quad)

        let weighted = (areaScore * 0.18)
            + (aspectScore * 0.24)
            + (centerednessScore * 0.10)
            + (skewScore * 0.20)
            + (textScore * 0.16)
            + (edgeMarginScore * 0.12)
        let totalScore = clamp01(weighted)

        return CandidateScore(
            quad: quad,
            areaRatio: areaRatio,
            areaScore: areaScore,
            aspectScore: aspectScore,
            centerednessScore: centerednessScore,
            skewScore: skewScore,
            textScore: textScore,
            edgeMarginScore: edgeMarginScore,
            totalScore: totalScore
        )
    }

    private func normalizedAreaScore(for areaRatio: Double) -> Double {
        clamp01(1 - abs(areaRatio - 0.58) / 0.48)
    }

    private func edgeMarginScore(for quad: CropQuad) -> Double {
        let minMargin = quad.points
            .map { point in
                min(
                    Double(point.x),
                    Double(point.y),
                    Double(1 - point.x),
                    Double(1 - point.y)
                )
            }
            .min() ?? 0
        return clamp01((minMargin - 0.015) / 0.075)
    }

    private func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func refinementVariants(for quad: CropQuad) -> [CropQuad] {
        let original = quad.clamped()
        let inset15 = applyInsets(to: original, top: 0.015, right: 0.015, bottom: 0.015, left: 0.015)
        let inset30 = applyInsets(to: original, top: 0.030, right: 0.030, bottom: 0.030, left: 0.030)
        let bottomFocused = applyInsets(to: original, top: 0.005, right: 0, bottom: 0.025, left: 0)
        let outward15 = applyInsets(to: original, top: -0.015, right: -0.015, bottom: -0.015, left: -0.015)
        return [original, inset15, inset30, bottomFocused, outward15]
    }

    private func applyInsets(
        to quad: CropQuad,
        top: CGFloat,
        right: CGFloat,
        bottom: CGFloat,
        left: CGFloat
    ) -> CropQuad {
        CropQuad(
            topLeft: CGPoint(
                x: quad.topLeft.x + left,
                y: quad.topLeft.y + top
            ),
            topRight: CGPoint(
                x: quad.topRight.x - right,
                y: quad.topRight.y + top
            ),
            bottomRight: CGPoint(
                x: quad.bottomRight.x - right,
                y: quad.bottomRight.y - bottom
            ),
            bottomLeft: CGPoint(
                x: quad.bottomLeft.x + left,
                y: quad.bottomLeft.y - bottom
            )
        ).clamped()
    }

    private func bestCandidate(in candidates: [CandidateScore]) -> CandidateScore? {
        var best: CandidateScore?
        for candidate in candidates {
            if let current = best, current.totalScore >= candidate.totalScore {
                continue
            }
            best = candidate
        }
        return best
    }

    private func aspectClosenessScore(_ aspect: Double) -> Double {
        let targets = [4.0 / 3.0, 16.0 / 9.0]
        let comparisons = targets.flatMap { [$0, 1.0 / $0] }

        let bestRelativeError = comparisons
            .map { abs(aspect - $0) / $0 }
            .min() ?? 1

        return max(0, 1 - min(bestRelativeError, 1))
    }

    private func skewSanityScore(for quad: CropQuad) -> Double {
        let p = quad.points
        guard p.count == 4 else { return 0 }

        let angles: [Double] = [
            cornerAngle(prev: p[3], current: p[0], next: p[1]),
            cornerAngle(prev: p[0], current: p[1], next: p[2]),
            cornerAngle(prev: p[1], current: p[2], next: p[3]),
            cornerAngle(prev: p[2], current: p[3], next: p[0])
        ]

        let rightAngle = Double.pi / 2
        let meanError = angles
            .map { abs($0 - rightAngle) / rightAngle }
            .reduce(0, +) / Double(angles.count)

        let nextPoints = Array(p.dropFirst()) + [p[0]]
        let edgeLengths: [Double] = zip(p, nextPoints).map { first, second in
            hypot(Double(second.x - first.x), Double(second.y - first.y))
        }

        let longest = edgeLengths.max() ?? 1
        let shortest = edgeLengths.min() ?? 1
        let balancePenalty = max(0, min(1, (longest - shortest) / max(longest, 0.0001)))

        let angleScore = max(0, 1 - meanError)
        let balanceScore = max(0, 1 - balancePenalty)
        return (angleScore * 0.75) + (balanceScore * 0.25)
    }

    private func cornerAngle(prev: CGPoint, current: CGPoint, next: CGPoint) -> Double {
        let v1x = Double(prev.x - current.x)
        let v1y = Double(prev.y - current.y)
        let v2x = Double(next.x - current.x)
        let v2y = Double(next.y - current.y)

        let dot = (v1x * v2x) + (v1y * v2y)
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        guard mag1 > 0, mag2 > 0 else { return 0 }

        let cosValue = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosValue)
    }

    private func textDensityBonus(in image: CIImage) -> Double {
        let sampled = resized(image: image, maxLongEdge: 900)
        guard let cgImage = ciContext.createCGImage(sampled, from: sampled.extent) else {
            return 0
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.025

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let count = request.results?.count ?? 0

        return min(Double(count) / 16.0, 1)
    }

    private func applyPerspectiveCorrection(to image: CIImage, quad: CropQuad) -> CIImage? {
        let extent = image.extent

        func ciPoint(from normalizedTopPoint: CGPoint) -> CIVector {
            let x = extent.minX + (normalizedTopPoint.x * extent.width)
            let y = extent.maxY - (normalizedTopPoint.y * extent.height)
            return CIVector(x: x, y: y)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(ciPoint(from: quad.topLeft), forKey: "inputTopLeft")
        filter.setValue(ciPoint(from: quad.topRight), forKey: "inputTopRight")
        filter.setValue(ciPoint(from: quad.bottomRight), forKey: "inputBottomRight")
        filter.setValue(ciPoint(from: quad.bottomLeft), forKey: "inputBottomLeft")

        return filter.outputImage
    }

    private func applyEnhancementMaximumClean(
        to image: CIImage,
        context: CIContext
    ) -> CIImage {
        _ = context
        var working = image
        // A) Fast global tone shaping for readability
        let controls = CIFilter.colorControls()
        controls.inputImage = working
        controls.contrast = 1.14
        controls.brightness = 0.02
        controls.saturation = 1.01
        working = controls.outputImage ?? working

        // B) Conservative highlight compression / shadow lift
        let hs = CIFilter.highlightShadowAdjust()
        hs.inputImage = working
        hs.highlightAmount = 0.90
        hs.shadowAmount = 0.10
        working = hs.outputImage ?? working

        // C) Mild luminance sharpening for text edges
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = working
        sharpen.sharpness = 0.45
        working = sharpen.outputImage ?? working

        return working
    }

    private func debugTimestamp() -> CFTimeInterval {
        #if DEBUG
        CACurrentMediaTime()
        #else
        0
        #endif
    }

    private func debugLogTiming(step: String, start: CFTimeInterval, assetIdentifier: String) {
        #if DEBUG
        guard start > 0 else { return }
        let elapsedMs = (CACurrentMediaTime() - start) * 1000
        print(
            "SlideCropTiming[\(assetIdentifier)] \(step): \(String(format: "%.1f", elapsedMs))ms"
        )
        #endif
    }

    private func debugLogCorrectedExtent(_ extent: CGRect, assetIdentifier: String) {
        #if DEBUG
        print(
            "SlideCropTiming[\(assetIdentifier)] corrected-extent: \(Int(extent.width.rounded()))x\(Int(extent.height.rounded()))"
        )
        #endif
    }

    private func debugLogDecision(
        assetIdentifier: String,
        best: CandidateScore,
        gap: Double,
        status: ProcessedStatus,
        refinementChanged: Bool
    ) {
        #if DEBUG
        print(
            "SlideCropDecision[\(assetIdentifier)] total=\(String(format: "%.3f", best.totalScore)) gap=\(String(format: "%.3f", gap)) area=\(String(format: "%.3f", best.areaScore)) aspect=\(String(format: "%.3f", best.aspectScore)) skew=\(String(format: "%.3f", best.skewScore)) edgeMargin=\(String(format: "%.3f", best.edgeMarginScore)) text=\(String(format: "%.3f", best.textScore)) status=\(status.rawValue) refinementChanged=\(refinementChanged)"
        )
        #endif
    }

    private func resized(image: CIImage, maxLongEdge: CGFloat) -> CIImage {
        let extent = image.extent.integral
        let longEdge = max(extent.width, extent.height)

        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / max(longEdge, 1)
        let transformed = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let newRect = CGRect(
            x: transformed.extent.origin.x,
            y: transformed.extent.origin.y,
            width: extent.width * scale,
            height: extent.height * scale
        )
        return transformed.cropped(to: newRect)
    }

    private func exportJPEG(image: CIImage, quality: CGFloat) throws -> URL {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw SlideCropError.outputFailed
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw SlideCropError.outputFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            throw SlideCropError.outputFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidecrop_\(UUID().uuidString).jpg")

        try encodedData.write(to: outputURL, options: .atomic)
        applyFileProtection(to: outputURL)
        return outputURL
    }

    private func makeThumbnail(from image: CIImage, maxLongEdge: CGFloat) -> UIImage? {
        let resizedImage = resized(image: image, maxLongEdge: maxLongEdge)
        guard let cg = ciContext.createCGImage(resizedImage, from: resizedImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private func persistSourceImageData(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidecrop_source_\(UUID().uuidString).img")

        do {
            try data.write(to: url, options: .atomic)
            applyFileProtection(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func applyFileProtection(to url: URL) {
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // Best-effort hardening only.
        }
    }

    private func loadManualSourceImage(assetIdentifier: String, sourceImageURL: URL?) async throws -> CIImage {
        if let asset = fetchAsset(with: assetIdentifier) {
            return try await loadHighResolutionCIImage(for: asset)
        }

        guard let sourceImageURL else {
            throw SlideCropError.assetNotFound
        }

        let data = try Data(contentsOf: sourceImageURL)
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw SlideCropError.imageDataUnavailable
        }

        return image
    }

    private func fetchAsset(with localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    private func loadHighResolutionCIImage(for asset: PHAsset) async throws -> CIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            options.version = .current

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, info in
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, var image = CIImage(data: data) else {
                    continuation.resume(throwing: SlideCropError.imageDataUnavailable)
                    return
                }

                image = image.oriented(forExifOrientation: Int32(orientation.rawValue))
                continuation.resume(returning: image)
            }
        }
    }
}

private struct CandidateScore {
    let quad: CropQuad
    let areaRatio: Double
    let areaScore: Double
    let aspectScore: Double
    let centerednessScore: Double
    let skewScore: Double
    let textScore: Double
    let edgeMarginScore: Double
    let totalScore: Double
}
