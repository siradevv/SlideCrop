import CoreGraphics

struct SnapEngine {
    let targetQuads: [CropQuad]
    let threshold: CGFloat

    func snapCorner(_ point: CGPoint) -> (point: CGPoint, didSnap: Bool) {
        var best = point
        var bestDist = threshold

        for quad in targetQuads {
            for i in 0..<4 {
                let target = quad.point(at: i)
                let dist = hypot(target.x - point.x, target.y - point.y)
                if dist < bestDist {
                    bestDist = dist
                    best = target
                }
            }
        }

        return (best, best != point)
    }

    func snapEdge(
        point1: CGPoint,
        point2: CGPoint
    ) -> (point1: CGPoint, point2: CGPoint, didSnap: Bool) {
        let userMid = CGPoint(
            x: (point1.x + point2.x) * 0.5,
            y: (point1.y + point2.y) * 0.5
        )

        var bestP1 = point1
        var bestP2 = point2
        var bestDist = threshold

        for quad in targetQuads {
            for i in 0..<4 {
                let next = (i + 1) % 4
                let tp1 = quad.point(at: i)
                let tp2 = quad.point(at: next)
                let targetMid = CGPoint(
                    x: (tp1.x + tp2.x) * 0.5,
                    y: (tp1.y + tp2.y) * 0.5
                )

                let dist = hypot(targetMid.x - userMid.x, targetMid.y - userMid.y)
                if dist < bestDist {
                    bestDist = dist
                    bestP1 = tp1
                    bestP2 = tp2
                }
            }
        }

        return (bestP1, bestP2, bestP1 != point1 || bestP2 != point2)
    }
}
