import CoreGraphics

struct CropQuad: Hashable, Codable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let full = CropQuad(
        topLeft: CGPoint(x: 0.08, y: 0.08),
        topRight: CGPoint(x: 0.92, y: 0.08),
        bottomRight: CGPoint(x: 0.92, y: 0.92),
        bottomLeft: CGPoint(x: 0.08, y: 0.92)
    )

    var points: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var centroid: CGPoint {
        let p = points
        let x = p.map(\.x).reduce(0, +) / CGFloat(p.count)
        let y = p.map(\.y).reduce(0, +) / CGFloat(p.count)
        return CGPoint(x: x, y: y)
    }

    var area: CGFloat {
        let p = points
        guard p.count == 4 else { return 0 }
        let sum1 = p[0].x * p[1].y + p[1].x * p[2].y + p[2].x * p[3].y + p[3].x * p[0].y
        let sum2 = p[0].y * p[1].x + p[1].y * p[2].x + p[2].y * p[3].x + p[3].y * p[0].x
        return abs(sum1 - sum2) * 0.5
    }

    func clamped() -> CropQuad {
        CropQuad(
            topLeft: topLeft.clampedUnit,
            topRight: topRight.clampedUnit,
            bottomRight: bottomRight.clampedUnit,
            bottomLeft: bottomLeft.clampedUnit
        )
    }

    func point(at index: Int) -> CGPoint {
        switch index {
        case 0: return topLeft
        case 1: return topRight
        case 2: return bottomRight
        default: return bottomLeft
        }
    }

    mutating func updatePoint(at index: Int, to value: CGPoint) {
        switch index {
        case 0: topLeft = value
        case 1: topRight = value
        case 2: bottomRight = value
        default: bottomLeft = value
        }
    }
}

private extension CGPoint {
    var clampedUnit: CGPoint {
        CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }
}
