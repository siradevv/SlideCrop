import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    func currentSettings() -> ProcessingSettings {
        ProcessingSettings(
            enhanceReadability: true,
            quality: .best
        )
    }
}
