import SwiftUI
import UIKit

enum SlideCropTheme {
    static let tint = Color(red: 0.34, green: 0.41, blue: 0.68)

    static let peach = Color(red: 0.96, green: 0.79, blue: 0.60)
    static let rose = Color(red: 0.90, green: 0.67, blue: 0.80)
    static let violet = Color(red: 0.71, green: 0.66, blue: 0.90)
    static let indigo = Color(red: 0.55, green: 0.61, blue: 0.86)

    static let pageBase = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1) : UIColor(red: 0.97, green: 0.97, blue: 0.985, alpha: 1) })
    static let readyBadge = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.42, green: 0.88, blue: 0.62, alpha: 1) : UIColor(red: 0.30, green: 0.74, blue: 0.53, alpha: 1) })
    static let reviewBadge = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.95, green: 0.72, blue: 0.40, alpha: 1) : UIColor(red: 0.87, green: 0.60, blue: 0.30, alpha: 1) })
    static let failedBadge = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.95, green: 0.48, blue: 0.48, alpha: 1) : UIColor(red: 0.84, green: 0.35, blue: 0.36, alpha: 1) })
    static let cropAccent = Color(red: 0.38, green: 0.94, blue: 0.76)

    static let panelStroke = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.18) : UIColor.white.withAlphaComponent(0.64) })
    static let panelShadow = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.40) : UIColor.black.withAlphaComponent(0.08) })

    static var pageGradient: LinearGradient {
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        return LinearGradient(
            colors: [
                peach.opacity(isDark ? 0.10 : 0.24),
                rose.opacity(isDark ? 0.09 : 0.20),
                violet.opacity(isDark ? 0.09 : 0.19),
                indigo.opacity(isDark ? 0.12 : 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }



    static let imagePaneBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.44) })
    static let imagePaneStroke = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.20) : UIColor.white.withAlphaComponent(0.60) })
    static let placeholderFill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.58) })
    static let mutedCapsuleBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.16) : UIColor.white.withAlphaComponent(0.50) })

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.41, green: 0.53, blue: 0.84),
                Color(red: 0.48, green: 0.43, blue: 0.79)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct SlideCropPageBackground: View {
    var body: some View {
        ZStack {
            SlideCropTheme.pageBase
                .ignoresSafeArea()

            SlideCropTheme.pageGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [SlideCropTheme.peach.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 24,
                endRadius: 430
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [SlideCropTheme.indigo.opacity(0.21), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }
}

private struct SlideCropCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SlideCropTheme.panelStroke, lineWidth: 1)
            )
            .shadow(color: SlideCropTheme.panelShadow, radius: 16, y: 8)
    }
}

extension View {
    func slideCropCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(SlideCropCardModifier(cornerRadius: cornerRadius))
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
