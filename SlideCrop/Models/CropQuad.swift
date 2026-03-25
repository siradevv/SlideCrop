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

    var isConvex: Bool {
        let p = points
        guard p.count == 4 else { return false }
        var sign: Int?
        for i in 0..<4 {
            let a = p[i]
            let b = p[(i + 1) % 4]
            let c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-10 { return false }
            let s = cross > 0 ? 1 : -1
            if let existing = sign, existing != s { return false }
            sign = s
        }
        return true
    }

    func snappedToAspectRatio(_ ratio: CGFloat, imageAspect: CGFloat) -> CropQuad {
        let center = centroid
        let adjustedRatio = ratio * (1.0 / max(imageAspect, 0.001))

        var w: CGFloat
        var h: CGFloat

        if adjustedRatio >= 1 {
            w = min(0.9, max(0.2, (points.map(\.x).max() ?? 0.92) - (points.map(\.x).min() ?? 0.08)))
            h = w / adjustedRatio
            if h > 0.9 { h = 0.9; w = h * adjustedRatio }
        } else {
            h = min(0.9, max(0.2, (points.map(\.y).max() ?? 0.92) - (points.map(\.y).min() ?? 0.08)))
            w = h * adjustedRatio
            if w > 0.9 { w = 0.9; h = w / adjustedRatio }
        }

        let halfW = w / 2
        let halfH = h / 2
        let cx = min(max(center.x, halfW), 1 - halfW)
        let cy = min(max(center.y, halfH), 1 - halfH)

        return CropQuad(
            topLeft: CGPoint(x: cx - halfW, y: cy - halfH),
            topRight: CGPoint(x: cx + halfW, y: cy - halfH),
            bottomRight: CGPoint(x: cx + halfW, y: cy + halfH),
            bottomLeft: CGPoint(x: cx - halfW, y: cy + halfH)
        ).clamped()
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
