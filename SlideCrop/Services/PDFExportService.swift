import UIKit

enum PDFLayout: String, CaseIterable, Identifiable {
    case one = "1 per page"
    case two = "2 per page"
    case four = "4 per page"
    case six = "6 per page"
    case eight = "8 per page"
    case ten = "10 per page"

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .one, .two: return 1
        case .four, .six, .eight, .ten: return 2
        }
    }

    var rows: Int {
        switch self {
        case .one: return 1
        case .two: return 2
        case .four: return 2
        case .six: return 3
        case .eight: return 4
        case .ten: return 5
        }
    }

    var slidesPerPage: Int { columns * rows }
}

enum PDFOrientation: String, CaseIterable, Identifiable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .portrait: return "rectangle.portrait"
        case .landscape: return "rectangle"
        }
    }

    var pageSize: CGSize {
        switch self {
        case .portrait: return CGSize(width: 595, height: 842)
        case .landscape: return CGSize(width: 842, height: 595)
        }
    }
}

enum PDFExportService {
    static func exportPDF(from items: [ProcessedItem], layout: PDFLayout = .one, orientation: PDFOrientation = .portrait) throws -> URL {
        let pageSize = orientation.pageSize
        let margin: CGFloat = 36
        let spacing: CGFloat = 16
        let drawableRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: format
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlideCrop-export-\(timestamp).pdf")

        let images: [UIImage] = items.compactMap { item in
            guard let imageURL = item.processedImageURL,
                  let data = try? Data(contentsOf: imageURL),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }

        let chunked = stride(from: 0, to: images.count, by: layout.slidesPerPage).map {
            Array(images[$0..<min($0 + layout.slidesPerPage, images.count)])
        }

        try renderer.writePDF(to: outputURL) { context in
            for page in chunked {
                autoreleasepool {
                    context.beginPage()

                    let cols = layout.columns
                    let rows = layout.rows
                    let totalHSpacing = spacing * CGFloat(cols - 1)
                    let totalVSpacing = spacing * CGFloat(rows - 1)
                    let cellWidth = (drawableRect.width - totalHSpacing) / CGFloat(cols)
                    let cellHeight = (drawableRect.height - totalVSpacing) / CGFloat(rows)

                    for (index, image) in page.enumerated() {
                        let col = index % cols
                        let row = index / cols
                        let cellRect = CGRect(
                            x: drawableRect.minX + CGFloat(col) * (cellWidth + spacing),
                            y: drawableRect.minY + CGFloat(row) * (cellHeight + spacing),
                            width: cellWidth,
                            height: cellHeight
                        )
                        let fitted = fitRect(imageSize: image.size, into: cellRect)
                        image.draw(in: fitted)
                    }
                }
            }
        }

        return outputURL
    }

    private static func fitRect(imageSize: CGSize, into rect: CGRect) -> CGRect {
        let widthRatio = rect.width / imageSize.width
        let heightRatio = rect.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        return CGRect(
            x: rect.midX - scaledWidth / 2,
            y: rect.midY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }
}
