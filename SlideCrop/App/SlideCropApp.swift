import SwiftUI

@main
struct SlideCropApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(SlideCropTheme.tint)
        }
    }
}
