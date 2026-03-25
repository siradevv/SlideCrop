import SwiftUI

@main
struct SlideCropApp: App {
    init() {
        cleanupStaleTempFiles()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(SlideCropTheme.tint)
        }
    }

    private func cleanupStaleTempFiles() {
        Task.detached(priority: .background) {
            let fm = FileManager.default
            let tmpDir = fm.temporaryDirectory
            guard let files = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: [.creationDateKey]) else { return }

            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            for file in files where file.lastPathComponent.hasPrefix("slidecrop_") || file.lastPathComponent.hasPrefix("SlideCrop-export-") {
                guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                      let created = attrs.creationDate,
                      created < cutoff else { continue }
                try? fm.removeItem(at: file)
            }
        }
    }
}
