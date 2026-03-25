import Foundation
import UIKit

enum ProcessedStatus: String, CaseIterable, Codable {
    case auto = "AUTO"
    case review = "REVIEW"
    case failed = "FAILED"
}

struct ProcessedItem: Identifiable {
    var id = UUID()
    let assetIdentifier: String
    var originalThumbnail: UIImage?
    var processedThumbnail: UIImage?
    var sourceImageURL: URL?
    var processedImageURL: URL?
    var confidenceScore: Double
    var status: ProcessedStatus
    var cropQuad: CropQuad?
    var errorMessage: String?
    var canReplaceOriginal: Bool = true
    var canManualAdjust: Bool = true
    var isEnhanced: Bool = true
}
