import SwiftUI

struct HeroCropIconView: View {
    @State private var isStraightened = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SlideCropTheme.peach.opacity(0.72),
                            SlideCropTheme.rose.opacity(0.62),
                            SlideCropTheme.indigo.opacity(0.68)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(HeroGridOverlay().opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 20, y: 14)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .frame(width: 160, height: 116)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.black.opacity(0.06)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(10)
                }
                .rotationEffect(.degrees(isStraightened ? 0 : -13))
                .offset(x: isStraightened ? 0 : -18, y: isStraightened ? 0 : -10)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 9)
                .animation(
                    .easeInOut(duration: 2.3).repeatForever(autoreverses: true),
                    value: isStraightened
                )
        }
        .padding(28)
        .onAppear {
            isStraightened = true
        }
    }
}

private struct HeroGridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let spacing: CGFloat = 30

                var x: CGFloat = 0
                while x <= proxy.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    x += spacing
                }

                var y: CGFloat = 0
                while y <= proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}
