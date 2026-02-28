import CoreGraphics
import Foundation

enum ProcessingQuality: String, CaseIterable, Identifiable {
    case fast
    case best

    var id: String { rawValue }

    var detectionLongEdge: CGFloat {
        switch self {
        case .fast:
            return 1000
        case .best:
            return 1400
        }
    }
}

struct ProcessingSettings {
    var enhanceReadability: Bool
    var quality: ProcessingQuality
}
