import SwiftUI

@main
struct BrewStoreApp: App {
    @StateObject private var manager = HomebrewManager()

    var body: some Scene {
        WindowGroup {
            BrewStoreRootView(manager: manager)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}
