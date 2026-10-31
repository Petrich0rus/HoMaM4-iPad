import SwiftUI

/// First launch: pick the GOG game folder (the one containing `Data` and `maps`).
struct SetupView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var picking = false
    @State private var copyMode = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64)).foregroundStyle(.tint)
            Text("Heroes of Might and Magic IV").font(.largeTitle.bold())
            Text("This app ships no game files. Choose your own GOG game folder, the one that contains “Data” and “maps”.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 480)
            if case .failed(let message) = library.state {
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 480)
            }
            Button("Choose game folder…") { copyMode = false; picking = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Copy the game into the app instead…") { copyMode = true; picking = true }
                .font(.footnote)
            Text("You can also drop the folders into this app’s Documents using the Files app.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(32)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task { copyMode ? await library.copyAndAdopt(url) : await library.adopt(url) }
        }
    }
}
