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

    private init(title: String, levels: [Level], compositor: H4TerrainCompositor) {
        self.title = title
        self.levels = levels
        self.compositor = compositor
        contentRect = levels[0].canvas.contentRect
    }

    /// Loads a map. Synchronous and heavy: call off the main thread. `progress` gets a fraction and a message.
    static func load(url: URL, store: H4ResourceStore, progress: @Sendable (Double, String) -> Void) throws -> MapSession {
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
        var levels: [Level] = []
        for level in 0..<terrain.levels {
            let base = 0.40 + 0.60 * Double(level) / Double(terrain.levels)
            progress(base, "Loading textures and objects (level \(level + 1) of \(terrain.levels))…")
            let objects = try H4MapObjectRender.drawList(objects: body.objects, level: level, region: region, models: models)
            progress(base + 0.30 / Double(terrain.levels), "Preparing the terrain (level \(level + 1) of \(terrain.levels))…")
            let plan = try compositor.prepare(terrain: terrain, level: level, region: region)
            let canvas = try H4MapCanvas(terrain: terrain, level: level, objects: body.objects, models: models)
            levels.append(Level(canvas: canvas, plan: plan, objects: objects))
        }
        guard compositor.missingTextures.isEmpty, compositor.missingMasks.isEmpty, models.missingModels.isEmpty else {
            let all = compositor.missingTextures.union(compositor.missingMasks).union(models.missingModels)
            throw H4Error.malformed("missing game resources: \(all.sorted().prefix(3).joined(separator: ", "))")
        }
        progress(1, "Done")
        return MapSession(title: scenario.name.isEmpty ? url.deletingPathExtension().lastPathComponent : scenario.name,
                          levels: levels, compositor: compositor)
    }

    /// Renders one tile; safe to call from any number of threads.
    func tileImage(level: Int, request: H4MapCanvas.TileRequest) throws -> CGImage {
        let l = levels[level]
        let image = try compositor.render(plan: l.plan, pixelRect: request.pixelRect, scale: request.scale, objects: l.objects)
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
