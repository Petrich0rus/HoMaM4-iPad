import SwiftUI

/// Map list (sidebar) and map detail.
struct MapBrowserView: View {
    @EnvironmentObject var library: GameLibrary
    @State var selection: MapEntry.ID?
    @State private var search = ""
    #if DEBUG
    @State private var touring = false
    @State private var playing = false
    #endif

    private var filtered: [MapEntry] {
        search.isEmpty ? library.maps : library.maps.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { MapRow(entry: $0) }
                .navigationTitle("Maps (\(library.maps.count))")
                .searchable(text: $search)
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Change game folder", systemImage: "folder") { library.forgetFolder() }
                    }
                }
        } detail: {
            if let entry = library.maps.first(where: { $0.id == selection }) {
                MapDetailView(entry: entry).id(entry.id)
            } else {
                ContentUnavailableView("Select a map", systemImage: "map")
            }
        }
        .onAppear(perform: selectFromLaunchArgument)
        #if DEBUG
        .onAppear { if AutoTour.isRequested { touring = true } else if AutoPlay.isRequested { playing = true } }
        .fullScreenCover(isPresented: $touring) { AutoTourView() }
        .fullScreenCover(isPresented: $playing) { AutoPlayView() }
        #endif
    }
}

extension MapBrowserView {
    /// Developer aid: `-H4SelectMap <text>` preselects the first map whose path contains the text.
    func selectFromLaunchArgument() {
        guard selection == nil, let key = UserDefaults.standard.string(forKey: "H4SelectMap") else { return }
        selection = library.maps.first { $0.path.localizedCaseInsensitiveContains(key) }?.id
    }
}

struct MapRow: View {
    let entry: MapEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title).font(.headline)
            if let info = entry.info {
                Text("\(entry.sizeLabel ?? "") · \(info.levels) level\(info.levels > 1 ? "s" : "") · \(info.players) players · \(MapEntry.difficultyName(info.difficulty))")
                    .font(.caption).foregroundStyle(.secondary)
                if let d = info.description.nilIfEmpty {
                    Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text("Unsupported").font(.caption.bold()).foregroundStyle(.orange)
                Text(entry.error ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .tag(entry.id)
    }
}
