import CoreGraphics
import Foundation
import H4Kit

/// Everything needed to draw one open map: scenario terrain and objects, one shared compositor and model library
/// (both safe for the concurrent tile draws of CATiledLayer), and per level the canvas geometry, resolved terrain
/// draw plan and object draw list of the whole map.
final class MapSession: @unchecked Sendable {
    struct Level {
        let canvas: H4MapCanvas
        let plan: H4TerrainCompositor.Plan
        let objects: H4ObjectDrawList
    }

    let title: String
    let levels: [Level]
    /// Content rectangle (scale-1 canvas pixels) shared by all levels.
    let contentRect: H4TerrainCompositor.PixelRect
    private let compositor: H4TerrainCompositor
    /// Object draw lists the tiles use. Equal to `levels[i].objects` until a game replaces them (`setObjects`).
    private let liveLock = NSLock()
    private var liveObjects: [H4ObjectDrawList]
    private var liveGeneration = 0

    private init(title: String, levels: [Level], compositor: H4TerrainCompositor) {
        self.title = title
        self.levels = levels
        self.compositor = compositor
        liveObjects = levels.map(\.objects)
        contentRect = levels[0].canvas.contentRect
    }

    /// Replaces the draw list of a level (game screen); tiles drawn from now on use it. Thread-safe.
    func setObjects(_ list: H4ObjectDrawList, level: Int) {
        liveLock.lock(); liveObjects[level] = list; liveGeneration += 1; liveLock.unlock()
    }

    /// Counter bumped by every `setObjects`: a tile that finished drawing under an older value is stale.
    var generation: Int {
        liveLock.lock(); defer { liveLock.unlock() }
        return liveGeneration
    }

    private func objects(level: Int) -> H4ObjectDrawList {
        liveLock.lock(); defer { liveLock.unlock() }
        return liveObjects[level]
    }

    /// The started game that goes with a `MapSession` (see `loadGame`).
    struct GameParts {
        let game: H4Game
        let session: H4GameSession
        let render: H4GameRender
    }

    /// Loads a map. Synchronous and heavy: call off the main thread. `progress` gets a fraction and a message.
    static func load(url: URL, store: H4ResourceStore, progress: @Sendable (Double, String) -> Void) throws -> MapSession {
        try build(url: url, store: store, start: nil, progress: progress).0
    }

    /// Loads a map and starts a game on it (seed, difficulty): the draw lists are the ones of the started game.
    static func loadGame(url: URL, store: H4ResourceStore, seed: UInt32, difficulty: Int,
                         progress: @Sendable (Double, String) -> Void) throws -> (MapSession, GameParts) {
        let (session, parts) = try build(url: url, store: store, start: (seed, difficulty), progress: progress)
        return (session, parts!)
    }

    private static func build(url: URL, store: H4ResourceStore, start: (seed: UInt32, difficulty: Int)?,
                              progress: @Sendable (Double, String) -> Void) throws -> (MapSession, GameParts?) {
        progress(0.02, "Reading the scenario…")
        let scenario = try H4Scenario(fileData: Data(contentsOf: url))
        progress(0.10, "Reading the terrain…")
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        progress(0.25, "Reading the objects…")
        let body = try H4ScenarioBody(scenario: scenario, resolver: H4ObjectClassResolver(resources: store))
        guard case .complete = body.stop else {
            throw H4Error.malformed("object list unreadable beyond body offset \(body.stop.offset)")
        }
        let compositor = try H4TerrainCompositor(store: store)
        let models = H4ObjectModelLibrary(store: store)
        let region = H4MapTerrainRender.Region.whole(size: scenario.size)
        var parts: GameParts?
        if let start {
            progress(0.30, "Starting the game…")
            let tables = try H4GameTables(store: store)
            let game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: start.seed, difficulty: start.difficulty)
            let gameSession = try H4GameSession(game: game, scenario: scenario, resources: store, tables: tables, ruleset: .v2)
            parts = GameParts(game: game, session: gameSession, render: H4GameRender(store: store, tables: tables, models: models))
        }
        var levels: [Level] = []
        for level in 0..<terrain.levels {
            let base = 0.40 + 0.60 * Double(level) / Double(terrain.levels)
            progress(base, "Loading textures and objects (level \(level + 1) of \(terrain.levels))…")
            let objects: H4ObjectDrawList
            if let parts {
                objects = try parts.render.drawList(objects: parts.session.scenarioObjects, game: parts.game, level: level, region: region,
                                                    state: parts.session.renderState)
            } else {
                objects = try H4MapObjectRender.drawList(objects: body.objects, level: level, region: region, models: models)
            }
            progress(base + 0.30 / Double(terrain.levels), "Preparing the terrain (level \(level + 1) of \(terrain.levels))…")
            let plan = try compositor.prepare(terrain: terrain, level: level, region: region)
            let canvas = try H4MapCanvas(terrain: terrain, level: level, objects: body.objects, models: models)
            levels.append(Level(canvas: canvas, plan: plan, objects: objects))
        }
        var missingGame: Set<String> = []
        if let parts { missingGame = parts.render.missingActors.union(parts.render.missingSequences).union(parts.render.missingFlags) }
        guard compositor.missingTextures.isEmpty, compositor.missingMasks.isEmpty, models.missingModels.isEmpty, missingGame.isEmpty else {
            let all = compositor.missingTextures.union(compositor.missingMasks).union(models.missingModels).union(missingGame)
            throw H4Error.malformed("missing game resources: \(all.sorted().prefix(3).joined(separator: ", "))")
        }
        progress(1, "Done")
        return (MapSession(title: scenario.name.isEmpty ? url.deletingPathExtension().lastPathComponent : scenario.name,
                           levels: levels, compositor: compositor), parts)
    }

    /// Renders one tile; safe to call from any number of threads.
    func tileImage(level: Int, request: H4MapCanvas.TileRequest) throws -> CGImage {
        let l = levels[level]
        let image = try compositor.render(plan: l.plan, pixelRect: request.pixelRect, scale: request.scale, objects: objects(level: level))
        guard let cg = image.cgImage() else { throw H4Error.malformed("empty tile") }
        return cg
    }
}

/// What the long-press popup shows.
struct MapCellInfo: Equatable {
    let row: Int, column: Int
    let terrain: String
    let objectModel: String?
    let objectClass: String?
}

extension MapSession {
    /// Info for the cell under a point given in scale-1 canvas pixels, nil outside the map.
    func cellInfo(level: Int, canvasX: Double, canvasY: Double) -> MapCellInfo? {
        let canvas = levels[level].canvas
        guard let cell = canvas.cell(atX: canvasX, y: canvasY),
              let terrain = canvas.terrainName(row: cell.row, column: cell.column) else { return nil }
        let object = canvas.object(row: cell.row, column: cell.column)
        return MapCellInfo(row: cell.row, column: cell.column, terrain: terrain,
                           objectModel: object?.modelName, objectClass: object?.className)
    }
}
