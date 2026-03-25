import UIKit

enum HapticService {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func lightImpact() {
        lightGenerator.impactOccurred()
    }

    static func successNotification() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func errorNotification() {
        notificationGenerator.notificationOccurred(.error)
    }
}
