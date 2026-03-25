import SwiftUI
import UIKit

struct CropOverlayView: View {
    @Binding var quad: CropQuad
    let image: UIImage?
    var snapEngine: SnapEngine?
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?

    @State private var activeHandleIndex: Int?
    @State private var activeEdgeIndex: Int?
    @State private var dragStartQuad: CropQuad?
    @State private var didFireSnapHaptic = false

    init(
        quad: Binding<CropQuad>,
        image: UIImage? = nil,
        snapEngine: SnapEngine? = nil,
        onInteractionBegan: (() -> Void)? = nil,
        onInteractionEnded: (() -> Void)? = nil
    ) {
        _quad = quad
        self.image = image
        self.snapEngine = snapEngine
        self.onInteractionBegan = onInteractionBegan
        self.onInteractionEnded = onInteractionEnded
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = quad.points.map { point in
                CGPoint(x: point.x * size.width, y: point.y * size.height)
            }

            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                    path.addLine(to: points[2])
                    path.addLine(to: points[3])
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))

                Path { path in
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                    path.addLine(to: points[2])
                    path.addLine(to: points[3])
                    path.closeSubpath()
                }
                .stroke(Color.black.opacity(0.55), lineWidth: 2.4)

                Path { path in
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                    path.addLine(to: points[2])
                    path.addLine(to: points[3])
                    path.closeSubpath()
                }
                .stroke(SlideCropTheme.cropAccent, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

                if let snapEngine {
                    ForEach(0..<snapEngine.targetQuads.count, id: \.self) { qi in
                        let tp = snapEngine.targetQuads[qi].points.map { p in
                            CGPoint(x: p.x * size.width, y: p.y * size.height)
                        }
                        Path { path in
                            path.move(to: tp[0])
                            for p in tp.dropFirst() { path.addLine(to: p) }
                            path.closeSubpath()
                        }
                        .stroke(
                            SlideCropTheme.cropAccent.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                    }
                }

                ForEach(0..<4, id: \.self) { index in
                    let next = (index + 1) % 4
                    let midpoint = CGPoint(
                        x: (points[index].x + points[next].x) * 0.5,
                        y: (points[index].y + points[next].y) * 0.5
                    )

                    Rectangle()
                        .fill(Color.black.opacity(0.65))
                        .overlay(
                            Rectangle()
                                .stroke(SlideCropTheme.cropAccent, lineWidth: 1)
                        )
                        .frame(width: 12, height: 12)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel(Self.edgeLabel(for: index))
                        .accessibilityHint("Drag to adjust crop edge")
                        .position(midpoint)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if activeEdgeIndex != index {
                                        activeEdgeIndex = index
                                        activeHandleIndex = nil
                                        dragStartQuad = quad
                                        onInteractionBegan?()
                                        HapticService.lightImpact()
                                    }

                                    let baselineQuad = dragStartQuad ?? quad
                                    let p1n = baselineQuad.point(at: index)
                                    let p2n = baselineQuad.point(at: next)

                                    let p1 = CGPoint(x: p1n.x * size.width, y: p1n.y * size.height)
                                    let p2 = CGPoint(x: p2n.x * size.width, y: p2n.y * size.height)
                                    let edge = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
                                    let edgeLength = max(hypot(edge.x, edge.y), 0.0001)

                                    // Perpendicular unit vector for this edge.
                                    let normal = CGPoint(x: -edge.y / edgeLength, y: edge.x / edgeLength)
                                    let projection = (value.translation.width * normal.x) + (value.translation.height * normal.y)
                                    let offset = CGPoint(x: normal.x * projection, y: normal.y * projection)
                                    let normalizedOffset = CGPoint(
                                        x: offset.x / max(size.width, 1),
                                        y: offset.y / max(size.height, 1)
                                    )

                                    var moved = baselineQuad
                                    moved.updatePoint(
                                        at: index,
                                        to: CGPoint(x: p1n.x + normalizedOffset.x, y: p1n.y + normalizedOffset.y)
                                    )
                                    moved.updatePoint(
                                        at: next,
                                        to: CGPoint(x: p2n.x + normalizedOffset.x, y: p2n.y + normalizedOffset.y)
                                    )

                                    if let snapEngine {
                                        let (s1, s2, didSnap) = snapEngine.snapEdge(
                                            point1: moved.point(at: index),
                                            point2: moved.point(at: next)
                                        )
                                        if didSnap {
                                            moved.updatePoint(at: index, to: s1)
                                            moved.updatePoint(at: next, to: s2)
                                            if !didFireSnapHaptic {
                                                HapticService.lightImpact()
                                                didFireSnapHaptic = true
                                            }
                                        } else {
                                            didFireSnapHaptic = false
                                        }
                                    }

                                    let clamped = moved.clamped()
                                    guard clamped.isConvex else { return }
                                    quad = clamped
                                }
                                .onEnded { _ in
                                    activeEdgeIndex = nil
                                    dragStartQuad = nil
                                    didFireSnapHaptic = false
                                    onInteractionEnded?()
                                }
                        )
                }

                ForEach(0..<4, id: \.self) { index in
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 16, height: 16)

                        Circle()
                            .stroke(SlideCropTheme.cropAccent, lineWidth: 1.8)
                            .frame(width: 22, height: 22)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Self.cornerLabel(for: index))
                    .accessibilityHint("Drag to adjust crop corner")
                    .position(points[index])
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if activeHandleIndex != index {
                                        activeHandleIndex = index
                                        activeEdgeIndex = nil
                                        dragStartQuad = quad
                                        onInteractionBegan?()
                                        HapticService.lightImpact()
                                    }

                                    let baselineQuad = dragStartQuad ?? quad
                                    let startPoint = baselineQuad.point(at: index)
                                    activeHandleIndex = index

                                    let normalized = CGPoint(
                                        x: min(1, max(0, startPoint.x + (value.translation.width / max(size.width, 1)))),
                                        y: min(1, max(0, startPoint.y + (value.translation.height / max(size.height, 1))))
                                    )

                                    var finalPoint = normalized
                                    if let snapEngine {
                                        let (snapped, didSnap) = snapEngine.snapCorner(normalized)
                                        finalPoint = snapped
                                        if didSnap {
                                            if !didFireSnapHaptic {
                                                HapticService.lightImpact()
                                                didFireSnapHaptic = true
                                            }
                                        } else {
                                            didFireSnapHaptic = false
                                        }
                                    }

                                    var candidate = quad
                                    candidate.updatePoint(at: index, to: finalPoint)
                                    let clamped = candidate.clamped()
                                    guard clamped.isConvex else { return }
                                    quad = clamped
                                }
                                .onEnded { _ in
                                    activeHandleIndex = nil
                                    activeEdgeIndex = nil
                                    dragStartQuad = nil
                                    didFireSnapHaptic = false
                                    onInteractionEnded?()
                                }
                        )
                }

                if let activeHandleIndex {
                    let normalizedPoint = quad.point(at: activeHandleIndex)
                    let handlePoint = CGPoint(
                        x: normalizedPoint.x * size.width,
                        y: normalizedPoint.y * size.height
                    )

                    loupeView(normalizedPoint: normalizedPoint, canvasSize: size)
                        .position(loupePosition(for: handlePoint, canvasSize: size))
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.12), value: activeHandleIndex)
                } else if let activeEdgeIndex {
                    let next = (activeEdgeIndex + 1) % 4
                    let p1 = quad.point(at: activeEdgeIndex)
                    let p2 = quad.point(at: next)
                    let normalizedMidpoint = CGPoint(
                        x: (p1.x + p2.x) * 0.5,
                        y: (p1.y + p2.y) * 0.5
                    )
                    let edgePoint = CGPoint(
                        x: normalizedMidpoint.x * size.width,
                        y: normalizedMidpoint.y * size.height
                    )

                    loupeView(normalizedPoint: normalizedMidpoint, canvasSize: size)
                        .position(loupePosition(for: edgePoint, canvasSize: size))
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.12), value: activeEdgeIndex)
                }
            }
        }
    }

    private static func cornerLabel(for index: Int) -> String {
        switch index {
        case 0: return "Top left crop handle"
        case 1: return "Top right crop handle"
        case 2: return "Bottom right crop handle"
        default: return "Bottom left crop handle"
        }
    }

    private static func edgeLabel(for index: Int) -> String {
        switch index {
        case 0: return "Top edge handle"
        case 1: return "Right edge handle"
        case 2: return "Bottom edge handle"
        default: return "Left edge handle"
        }
    }

    @ViewBuilder
    private func loupeView(normalizedPoint: CGPoint, canvasSize: CGSize) -> some View {
        let diameter: CGFloat = 132
        let zoom: CGFloat = 2.8
        let zoomedWidth = canvasSize.width * zoom
        let zoomedHeight = canvasSize.height * zoom

        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: zoomedWidth, height: zoomedHeight)
                    .offset(
                        // Center the exact handle position under the loupe crosshair.
                        x: (zoomedWidth * 0.5) - (normalizedPoint.x * zoomedWidth),
                        y: (zoomedHeight * 0.5) - (normalizedPoint.y * zoomedHeight)
                    )
            } else {
                Color.black.opacity(0.35)
            }

            Crosshair()
                .stroke(SlideCropTheme.cropAccent, lineWidth: 1.2)
                .frame(width: 34, height: 34)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 3))
        .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.38), radius: 12, y: 8)
    }

    private func loupePosition(for point: CGPoint, canvasSize: CGSize) -> CGPoint {
        let diameter: CGFloat = 132
        let margin: CGFloat = 12
        let minX = (diameter * 0.5) + margin
        let maxX = canvasSize.width - (diameter * 0.5) - margin
        let minY = (diameter * 0.5) + margin
        let maxY = canvasSize.height - (diameter * 0.5) - margin

        // Keep the loupe away from the finger by snapping to the opposite side.
        let x = point.x < canvasSize.width * 0.5 ? maxX : minX
        let y = point.y < canvasSize.height * 0.5 ? maxY : minY

        return CGPoint(x: x, y: y)
    }
}

private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addLine(to: CGPoint(x: midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        return path
    }
}
