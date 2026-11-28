import SwiftUI

@main
struct SealPadApp: App {
    @State private var manager = DownloadManager()
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(manager)
                .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
                .task { await manager.boot() }
        }
    }
}
