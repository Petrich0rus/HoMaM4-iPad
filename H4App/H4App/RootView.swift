import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        switch library.state {
        case .ready:
            MapBrowserView()
        case .loading(let message):
            VStack(spacing: 16) {
                ProgressView()
                Text(message)
                if let p = library.scanProgress {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                        .frame(maxWidth: 280)
                    Text("\(p.done) / \(p.total) maps").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .needsFolder, .failed:
            SetupView()
        }
    }
}
