import SwiftUI

@main
struct SealPadApp: App {
    @State private var manager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(manager)
                .task { await manager.boot() }
        }
    }
}
