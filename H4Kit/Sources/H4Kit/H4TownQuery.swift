import Foundation

// Slice 8c — read-only queries of a v2 session for the town screen, and the map model override.
//
// Previews run the 8a command on a COPY of the town world and of the resources (both are value types), so a preview cannot
// disagree with the mutating call. Nothing here changes the session.

/// What the terrain query reads besides the town world: the game's resources and the terrain of the map, with caches.
final class H4TownAux {
    let store: H4ResourceStore
    let terrain: H4ScenarioTerrain
    var terrainCache: [Int: Int] = [:]
    var models: [String: H4AdventureObject] = [:]

    init(store: H4ResourceStore, terrain: H4ScenarioTerrain) { self.store = store; self.terrain = terrain }
}

extension H4GameSession {
    // MARK: previews (q1)

    /// nil when `build(town:building:)` would succeed now, else the exact 8a why-code it would give.
    public func buildStatus(town: Int, building: Int) -> String? {
        guard var w = townWorld else { return "bad-ruleset" }
        var res = resourceStore
        let r = w.build(["town": town, "building": building], current: currentPlayer, resources: &res)
        return r.ok ? nil : (r.why ?? "")
    }

    /// The dwelling of a town of the current player: creature id, creatures available now, and how many a `recruit` of
    /// everything available would recruit (limited by resources and by room in the garrison). nil when the town is not an own
    /// town, `building` is not 12...19, or the dwelling is not built.
    public func recruitPreview(town: Int, building: Int) -> (creature: Int, available: Int, maxAffordable: Int)? {
        guard var w = townWorld, let t = w.towns[town], t.owner == currentPlayer, (12...19).contains(building),
              t.mask >> building & 1 != 0 else { return nil }
        let creature = w.tables.dwelling(faction: t.faction, bit: building).creature
        let available = t.stock[building - 12] / H4Economy.stockPerCreature
        var res = resourceStore
        let r = w.recruit(["town": town, "building": building, "count": max(1, available)], current: currentPlayer, resources: &res)
        return (creature, available, r.ok ? (r.count ?? 0) : 0)
    }

    /// The result `transfer(from:to:count:)` would give now.
    public func transferPreview(from: [String: Int], to: [String: Int], count: Int? = nil) -> H4TownOp {
        guard var w = townWorld else { return H4TownOp(ok: false, why: "bad-ruleset", count: nil) }
        var c: [String: Any] = ["from": from, "to": to]
        if let count { c["count"] = count }
        return w.transfer(c, current: currentPlayer)
    }

    // MARK: queries (q2)

    /// The town of that object index (v2).
    public func town(_ index: Int) -> H4TownState? { townWorld?.towns[index] }

    /// R2 adventure-map model name of the town from its current mask.
    public func townModel(town index: Int) -> String? { townWorld?.towns[index]?.model }

    /// 8b R1a terrain id of the town on the session's map (the model of the town at the start of the game gives the footprint,
    /// so the background does not change when the town grows). -1 when the town or a resource is missing.
    public func townTerrain(town index: Int) -> Int {
        guard let aux = townAux, let start = townStartMask[index], let t = townWorld?.towns[index],
              scenarioObjects.indices.contains(index) else { return -1 }
        if let cached = aux.terrainCache[index] { return cached }
        let o = scenarioObjects[index]
        let name = H4TownRules.modelName(faction: t.faction, mask: start, right: t.right)
        let model: H4AdventureObject
        do {
            if let m = aux.models[name.lowercased()] { model = m } else {
                model = try H4AdventureObject(data: aux.store.data(for: "adv_object.\(name).h4d"))
                aux.models[name.lowercased()] = model
            }
        } catch { return -1 }
        guard let eh = model.edgesHorizontal, let ev = model.edgesVertical else { return -1 }
        let terrain = aux.terrain, level = Int(o.level)
        let rows = terrain.geometry.cellRows
        let inMap: (Int, Int) -> Bool = { x, y in (0..<terrain.levels).contains(level) && x >= 0 && x < rows.count && rows[x].contains(y) }
        let at: (Int, Int) -> Int = { x, y in Int(terrain.cells[level][x][y - rows[x].lowerBound].terrain) & 0x1f }
        let r = H4TownRender.terrain(x: Int(o.x), y: Int(o.y), width: model.width, height: model.height,
                                     edgesHorizontal: eh, edgesVertical: ev, inMap: inMap, terrainAt: at)
        aux.terrainCache[index] = r.terrain
        return r.terrain
    }

    /// Display name of a building of a faction (from table.buildings).
    public func buildingName(faction: Int, building: Int) -> String {
        townWorld?.tables.buildings.name(faction: faction, building: building) ?? "Building \(building)"
    }

    /// Cost of a building (7 resources), nil when the faction has no such building.
    public func buildingCost(faction: Int, building: Int) -> [Int]? { townWorld?.tables.buildings.cost(faction: faction, building: building) }

    /// Display name of a creature (singular or plural), from table.creatures.
    public func creatureName(_ id: Int, plural: Bool = false) -> String {
        guard let t = townWorld?.tables else { return "Creature \(id)" }
        let names = plural ? t.creaturePlurals : t.creatureNames
        if names.indices.contains(id) { return names[id] }
        return t.creatures.indices.contains(id) ? t.creatures[id].keyword : "Creature \(id)"
    }

    /// Unit cost of a creature (7 resources), nil for an unknown id.
    public func creatureCost(_ id: Int) -> [Int]? {
        guard let t = townWorld?.tables, t.creatures.indices.contains(id) else { return nil }
        return t.creatures[id].cost
    }

    // MARK: map model override (q3)

    /// Towns whose tier now differs from the tier at the start of the game, with the model derived from their mask.
    func townModelOverrides() -> [Int: String] {
        guard let w = townWorld else { return [:] }
        var out: [Int: String] = [:]
        for (i, t) in w.towns {
            guard let start = townStartMask[i], H4TownRules.tier(mask: t.mask) != H4TownRules.tier(mask: start) else { continue }
            out[i] = t.model
        }
        return out
    }
}

// MARK: - Labels

/// Texts the town screen shows for the why-codes of the 8a commands.
public enum H4TownLabels {
    /// Every why `build` can give.
    public static let buildWhys = ["faction-static-set", "not-allowed", "already-built", "requirements", "exclusive-partner", "built-today",
                                   "resources", "not-own-town", "not-current-player"]

    /// Label of a build status: nil (would succeed) is "Build".
    public static func build(_ why: String?) -> String {
        switch why {
        case nil: return "Build"
        case "already-built": return "Built"
        case "built-today": return "Already built today"
        case "resources": return "Not enough resources"
        case "requirements": return "Requires other buildings"
        case "exclusive-partner": return "Excludes a built building"
        case "not-allowed": return "Not allowed on this map"
        default: return "Unavailable"                                    // faction-static-set, not-own-town, not-current-player
        }
    }

    /// Label of a refused recruit or transfer.
    public static func troops(_ why: String?) -> String {
        switch why {
        case nil: return "Done"
        case "none-available": return "No creatures available"
        case "resources": return "Not enough resources"
        case "no-dwelling": return "That dwelling is not built"
        case "garrison-full": return "No free slot"
        case "bad-count": return "Invalid number"
        case "not-own", "not-own-town", "not-current-player": return "Not your troops"
        case "not-visiting": return "No hero is visiting this town"
        case "empty-source": return "Nothing to move"
        case "hero-slot": return "The hero cannot be moved"
        case "same-slot": return "Same slot"
        case "slot-occupied": return "That slot holds other creatures"
        case "bad-container", "bad-slot": return "Invalid slot"
        default: return why ?? "Refused"
        }
    }
}
