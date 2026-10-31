import SwiftUI

@main
struct H4AppApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
        }
    }
}
