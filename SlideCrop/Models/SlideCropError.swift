import Foundation

enum SlideCropError: LocalizedError {
    case assetNotFound
    case imageDataUnavailable
    case perspectiveFailed
    case outputFailed
    case permissionDenied
    case iCloudTimeout

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return "Unable to load the selected photo asset."
        case .imageDataUnavailable:
            return "Unable to read image data for this photo."
        case .perspectiveFailed:
            return "Perspective correction failed for this candidate."
        case .outputFailed:
            return "Failed to render the processed output image."
        case .permissionDenied:
            return "Photo library permission was denied."
        case .iCloudTimeout:
            return "Photo download from iCloud timed out. Check your network connection and try again."
        }
    }
}
