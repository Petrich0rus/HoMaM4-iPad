import Foundation
import H4Kit

let usage = """
usage:
  h4tool list    <archive.h4r>                 list entries of one archive
  h4tool summary <Data-dir>                    archives, entry counts, resource types
  h4tool verify  <Data-dir>                    decompress every resource and check sizes/CRC
  h4tool extract <Data-dir> <out-dir> [prefix] extract resources (aliases resolved)
  h4tool png     <Data-dir> <resource> <out-dir>  render a layers/animation/actor_sequence/bitmap_raw/
                                               adv_object/combat_object/terrain/font
                                               resource: one PNG per layer or frame
  h4tool text    <Data-dir> <font> "<text>" <out.png>  write text with a game font
  h4tool decode-all <Data-dir>                 decode every image resource and report failures
  h4tool maps    <maps-dir>                    list scenarios (.h4c, recursive): name, size, players
  h4tool objects <Data-dir> <maps-dir> [--histogram]  decode body sections and the object list of every
                                               scenario up to the first unsupported class
  h4tool check-body <Data-dir> <maps-dir>      check that the object list of every scenario ends exactly where
                                               its terrain starts (exit 2 on any mismatch or failure)
  h4tool minimap <Data-dir> <map.h4c> <out-prefix>  terrain minimap PNG per level (colours from the game textures)
  h4tool render  <Data-dir> <map.h4c> <out.png> [--level L] [--cells r0 c0 nr nc] [--scale k] [--no-objects] [--drawlist out.json]
                                               composite the terrain (bases, transitions, roads) and the objects of one level
                                               (default: level 0, whole map, scale 1; k in 1,2,4,8); --drawlist writes the
                                               object draw list as JSON [kind, model, x, y, layerIndex, column|null]
  h4tool render-all <Data-dir> <maps-dir> <out-dir> [--scale k] [--no-objects]
                                               render every level of every scenario (.h4c, recursive) to
                                               <out-dir>/<map path>.L<level>.png (exit 2 on any failure or missing resource)
"""

/// Decodes one image-bearing resource into named images, or nil if its type has no images.
func images(of name: String, data: Data) throws -> [(String, H4RGBAImage)]? {
    func frames(_ group: H4LayerGroup) -> [(String, H4RGBAImage)] {
        group.layers.filter { !$0.isEmpty }.map { ($0.name, $0.rgba()) }
    }
    switch name.split(separator: ".").first.map(String.init) ?? "" {
    case "layers": return frames(try H4LayerGroup(data: data))
    case "animation": return frames(try H4Animation(data: data).frames)
    case "actor_sequence": return frames(try H4ActorSequence(data: data).frames)
    case "bitmap_raw": return [("image", try H4RawBitmap(data: data).image)]
    case "adv_object": return frames(try H4AdventureObject(data: data).sprite.frames)
    case "combat_object": return frames(try H4CombatObject(data: data).sprite.frames)
    case "terrain":
        let texture = try H4TerrainTexture(data: data)
        return (0..<H4TerrainTexture.tileCount).map { (String(format: "tile_%02d", $0), texture.image(ofTile: $0)) }
    case "font":
        let font = try H4Font(data: data)
        return font.glyphs.indices.compactMap { i in
            let glyph = font.glyphs[i]
            guard glyph.width > 0, glyph.height > 0 else { return nil }
            return (String(format: "char_%03d", Int(font.firstCharacter) + i), font.render(glyph))
        }
    default: return nil
    }
}

let imageTypes = ["layers", "animation", "actor_sequence", "bitmap_raw", "adv_object", "combat_object", "terrain", "font"]

/// Relative paths of every `.h4c` below `dir`, sorted bytewise like Python's `sorted()`.
func mapPaths(in dir: String) -> [String] {
    let found = FileManager.default.enumerator(atPath: dir)?.compactMap { $0 as? String }
        .filter { $0.lowercased().hasSuffix(".h4c") } ?? []
    return found.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
}

/// Object records of a scenario; throws if the object list could not be read to its end.
func completeObjects(of scenario: H4Scenario, resolver: H4ObjectClassResolver) throws -> [H4ScenarioObject] {
    let body = try H4ScenarioBody(scenario: scenario, resolver: resolver)
    guard case .complete = body.stop else { throw H4Error.malformed("object list stopped at \(body.stop.offset)") }
    return body.objects
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else { fail(usage) }
let rest = Array(args.dropFirst())

do {
    switch (command, rest.count) {
    case ("list", 1):
        let archive = try H4RArchive(url: URL(fileURLWithPath: rest[0]))
        for e in archive.entries {
            let kind = e.aliasTarget.map { "-> \($0)" } ?? "\(e.storage) \(e.storedSize) -> \(e.size)"
            print("\(e.name)\t\(kind)")
        }
        print("\(archive.entries.count) entries")

    case ("summary", 1):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        for a in store.archives {
            print("\(a.url.lastPathComponent): \(a.entries.count) entries, \(a.entries.filter(\.isAlias).count) aliases")
        }
        var types: [String: Int] = [:]
        for name in store.names { types[name.split(separator: ".").first.map(String.init) ?? name, default: 0] += 1 }
        print("\(store.names.count) unique resources")
        for (t, n) in types.sorted(by: { $0.value > $1.value }) { print("  \(t): \(n)") }

    case ("verify", 1):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        var checked = 0, bytes = 0
        var failures: [String] = []
        // Check every physical entry of every archive, including ones shadowed by overrides.
        for archive in store.archives {
            for entry in archive.entries where !entry.isAlias {
                do { bytes += try archive.payload(of: entry).count; checked += 1 }
                catch { failures.append("\(archive.url.lastPathComponent): \(error)") }
            }
        }
        var aliases = 0
        var dangling: [String] = []
        for name in store.names where store.locate(name)?.entry.isAlias == true {
            do { _ = try store.resolve(name); aliases += 1 }
            catch H4Error.notFound(let target) { dangling.append("\(name) -> \(target)") } // broken in the shipped data
            catch { failures.append("alias \(name): \(error)") }
        }
        print("payloads OK: \(checked) (\(bytes / 1_048_576) MiB), aliases resolved: \(aliases), dangling aliases: \(dangling.count), failures: \(failures.count)")
        dangling.forEach { print("  WARN dangling alias in game data: \($0)") }
        failures.prefix(20).forEach { print("  FAIL \($0)") }
        if !failures.isEmpty { exit(2) }

    case ("extract", 2), ("extract", 3):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let out = URL(fileURLWithPath: rest[1])
        let report = H4Extraction.extract(store: store, to: out, prefix: rest.count == 3 ? rest[2] : "") { done, total in
            if done % 1000 == 0 || done == total { print("\(done)/\(total)") }
        }
        print("extracted \(report.written) resources to \(out.path), skipped \(report.failures.count)")
        report.failures.forEach { print("  SKIP \($0.name): \($0.error)") }

    case ("png", 3):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        guard let list = try images(of: rest[1], data: store.data(for: rest[1])) else {
            fail("'\(rest[1])' is not an image resource type")
        }
        let out = URL(fileURLWithPath: rest[2])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (i, (layerName, image)) in list.enumerated() {
            let safe = layerName.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" }
            let file = out.appendingPathComponent(String(format: "%03d_", i) + String(safe) + ".png")
            try image.pngData().write(to: file)
            print("\(file.lastPathComponent)\t\(image.width)×\(image.height)")
        }

    case ("text", 4):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let font = try H4Font(data: store.data(for: rest[1]))
        try font.render(text: rest[2], color: (240, 220, 160)).pngData().write(to: URL(fileURLWithPath: rest[3]))
        print("wrote \(rest[3])")

    case ("maps", 1):
        let dir = URL(fileURLWithPath: rest[0])
        let files = mapPaths(in: rest[0]).map { dir.appendingPathComponent($0) }
        var failed = 0
        for file in files {
            do {
                let s = try H4Scenario(fileData: Data(contentsOf: file))
                let humans = s.players.filter(\.humanPlayable).count
                let t = try H4ScenarioTerrain(scenario: s)
                let alts = t.alternativeStarts.isEmpty ? "" : "\tAMBIGUOUS \(t.alternativeStarts.map { $0 - t.start }), \(t.uncertainCells) uncertain cells"
                print("\(s.name)\t\(s.size)×\(s.size)\(s.levels == 2 ? " +sous-sol" : "")\t\(s.players.count) joueurs (\(humans) humains)\tdifficulté \(s.difficulty)\tv\(s.version)\tterrain @\(t.start)/\(s.body.count)\(alts)")
            } catch {
                failed += 1
                print("FAIL \(file.path.dropFirst(dir.path.count + 1)): \(error)")
            }
        }
        print("\(files.count - failed)/\(files.count) scenarios read")
        if failed > 0 { exit(2) }

    case ("objects", 2), ("objects", 3):
        let histogram = rest.count == 3
        if histogram && rest[2] != "--histogram" { fail(usage) }
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let resolver = H4ObjectClassResolver(resources: store)
        let dir = URL(fileURLWithPath: rest[1])
        let paths = mapPaths(in: rest[1])
        var classCounts: [String: Int] = [:]
        print("# population \(paths.count)")
        for rel in paths {
            let scenario: H4Scenario
            do { scenario = try H4Scenario(fileData: Data(contentsOf: dir.appendingPathComponent(rel))) }
            catch { print("\(rel)\tHEADER-FAIL\t\(error)"); continue }
            let sections: H4ScenarioSections
            do { sections = try H4ScenarioSections(scenario: scenario) }
            catch { print("\(rel)\tSECTIONS-FAIL\t\(error)"); continue }
            do {
                let body = try H4ScenarioBody(scenario: scenario, sections: sections, resolver: resolver)
                let why: String
                switch body.stop {
                case .complete: why = "complete"
                case let .stopped(_, reason): why = reason.description
                }
                print("\(rel)\tobjstart=\(body.objectListOffset)\tcount=\(body.declaredCount)\tdecoded=\(body.objects.count)\tstop=\(body.stop.offset)\t\(why)\tmismatch=0")
                for o in body.objects { classCounts[o.className, default: 0] += 1 }
            } catch {
                print("\(rel)\tOBJECTS-FAIL\t\(error)")
            }
        }
        if histogram {
            print("# class histogram (decoded records)")
            for (name, n) in classCounts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
                print("\(n)\t\(name)")
            }
        }

    case ("check-body", 2):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let resolver = H4ObjectClassResolver(resources: store)
        let dir = URL(fileURLWithPath: rest[1])
        let paths = mapPaths(in: rest[1])
        var good = 0
        for rel in paths {
            do {
                let scenario = try H4Scenario(fileData: Data(contentsOf: dir.appendingPathComponent(rel)))
                let body = try H4ScenarioBody(scenario: scenario, resolver: resolver)
                let terrain = try H4ScenarioTerrain(scenario: scenario)
                let ok: Bool
                if case .complete = body.stop { ok = body.stop.offset == terrain.start } else { ok = false }
                if ok { good += 1 }
                print("\(rel)\tobjend=\(body.stop.offset)\tterrain=\(terrain.start)\t\(ok ? "OK" : "MISMATCH")")
            } catch {
                print("\(rel)\tFAIL\t\(error)")
            }
        }
        print("# \(good)/\(paths.count) object lists end at the terrain start")
        if good != paths.count { exit(2) }

    case ("minimap", 3):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: rest[1])))
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        // Average colour of each base terrain texture (opaque pixels of all 100 tiles).
        var colours: [Int: (UInt8, UInt8, UInt8)] = [:]
        for (t, name) in H4TerrainCell.terrainNames.enumerated() {
            for v in 0..<2 {
                guard let tex = try? H4TerrainTexture(data: store.data(for: "terrain.\(name).\(v + 1).1.h4d")) else { continue }
                var sum = (0, 0, 0), count = 0
                for i in 0..<H4TerrainTexture.tileCount {
                    let img = tex.image(ofTile: i)
                    for p in stride(from: 0, to: img.pixels.count, by: 4) where img.pixels[p + 3] == 255 {
                        sum.0 += Int(img.pixels[p]); sum.1 += Int(img.pixels[p + 1]); sum.2 += Int(img.pixels[p + 2]); count += 1
                    }
                }
                if count > 0 { colours[t * 2 + v] = (UInt8(sum.0 / count), UInt8(sum.1 / count), UInt8(sum.2 / count)) }
            }
        }
        print("\(scenario.name): terrain at offset \(terrain.start) of \(scenario.body.count), alternatives \(terrain.alternativeStarts)")
        for level in 0..<terrain.levels {
            let img = terrain.minimap(level: level) { colours[Int($0.terrain) * 2 + Int($0.variant)] ?? (255, 0, 255) }
            let file = rest[2] + "_\(level).png"
            try img.pngData().write(to: URL(fileURLWithPath: file))
            print("wrote \(file) (\(img.width)×\(img.height))")
        }

    case ("decode-all", 1):
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        var counts: [String: (ok: Int, images: Int, failed: Int)] = [:]
        var failures: [String] = []
        for name in store.names {
            let type = name.split(separator: ".").first.map(String.init) ?? ""
            guard imageTypes.contains(type) else { continue }
            do {
                guard let list = try images(of: name, data: store.data(for: name)) else { continue }
                counts[type, default: (0, 0, 0)].ok += 1
                counts[type, default: (0, 0, 0)].images += list.count
            } catch H4Error.notFound(let target) {
                print("  WARN dangling alias in game data: \(name) -> \(target)")
            } catch {
                counts[type, default: (0, 0, 0)].failed += 1
                failures.append("\(name): \(error)")
            }
        }
        for (type, c) in counts.sorted(by: { $0.key < $1.key }) {
            print("\(type): \(c.ok) decoded (\(c.images) images), \(c.failed) failed")
        }
        failures.prefix(20).forEach { print("  FAIL \($0)") }
        if !failures.isEmpty { exit(2) }

    case ("render", 3...):
        var level = 0, cells: [Int]?, scale = 1, objectsOn = true, drawlist: String?
        var i = 3
        func intArgs(_ n: Int) -> [Int] {
            guard i + n < rest.count else { fail(usage) }
            let v = rest[(i + 1)...(i + n)].compactMap { Int($0) }
            guard v.count == n else { fail(usage) }
            i += n + 1
            return v
        }
        while i < rest.count {
            switch rest[i] {
            case "--level": level = intArgs(1)[0]
            case "--scale": scale = intArgs(1)[0]
            case "--cells": cells = intArgs(4)
            case "--no-objects": objectsOn = false; i += 1
            case "--drawlist":
                guard i + 1 < rest.count else { fail(usage) }
                drawlist = rest[i + 1]; i += 2
            default: fail(usage)
            }
        }
        guard [1, 2, 4, 8].contains(scale) else { fail("--scale must be 1, 2, 4 or 8") }
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: rest[1])))
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        let region = cells.map { H4MapTerrainRender.Region(row: $0[0], column: $0[1], rows: $0[2], columns: $0[3]) }
            ?? .whole(size: scenario.size)
        let compositor = try H4TerrainCompositor(store: store)
        let models = H4ObjectModelLibrary(store: store)
        let clock = ContinuousClock()
        var image: H4RGBAImage?
        var list: H4ObjectDrawList?
        let elapsed = try clock.measure {
            if objectsOn || drawlist != nil {
                let objects = try completeObjects(of: scenario, resolver: H4ObjectClassResolver(resources: store))
                list = try H4MapObjectRender.drawList(objects: objects, level: level, region: region, models: models)
            }
            image = try compositor.render(terrain: terrain, level: level, region: region, scale: scale,
                                          objects: objectsOn ? list : nil)
        }
        try image!.pngData().write(to: URL(fileURLWithPath: rest[2]))
        if let drawlist, let list { try list.json().write(to: URL(fileURLWithPath: drawlist)) }
        print("wrote \(rest[2]) (\(image!.width)×\(image!.height)) in \(elapsed)")
        if let list { print("# objects \(list.objectCount), draw items \(list.items.count)") }
        print("# missing textures \(compositor.missingTextures.count), missing masks \(compositor.missingMasks.count), missing models \(models.missingModels.count)")
        compositor.missingTextures.sorted().forEach { print("  MISSING texture \($0)") }
        compositor.missingMasks.sorted().forEach { print("  MISSING mask \($0)") }
        models.missingModels.sorted().forEach { print("  MISSING model \($0)") }
        if !compositor.missingTextures.isEmpty || !compositor.missingMasks.isEmpty || !models.missingModels.isEmpty { exit(2) }

    case ("render-all", 3...):
        var scale = 1, objectsOn = true
        var j = 3
        while j < rest.count {
            if rest[j] == "--scale", j + 1 < rest.count, let k = Int(rest[j + 1]) { scale = k; j += 2 }
            else if rest[j] == "--no-objects" { objectsOn = false; j += 1 }
            else { fail(usage) }
        }
        guard [1, 2, 4, 8].contains(scale) else { fail("--scale must be 1, 2, 4 or 8") }
        let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: rest[0]))
        let compositor = try H4TerrainCompositor(store: store)
        let models = H4ObjectModelLibrary(store: store)
        let resolver = H4ObjectClassResolver(resources: store)
        let dir = URL(fileURLWithPath: rest[1]), outDir = URL(fileURLWithPath: rest[2])
        let paths = mapPaths(in: rest[1])
        var rendered = 0, levels = 0, failed = 0
        for rel in paths {
            do {
                let scenario = try H4Scenario(fileData: Data(contentsOf: dir.appendingPathComponent(rel)))
                let terrain = try H4ScenarioTerrain(scenario: scenario)
                let objects = objectsOn ? try completeObjects(of: scenario, resolver: resolver) : []
                let stem = String(rel.dropLast(4))
                let file = outDir.appendingPathComponent(stem).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
                for level in 0..<terrain.levels {
                    levels += 1
                    do {
                        let region = H4MapTerrainRender.Region.whole(size: scenario.size)
                        let list = objectsOn ? try H4MapObjectRender.drawList(objects: objects, level: level, region: region, models: models) : nil
                        let image = try compositor.render(terrain: terrain, level: level, region: region, scale: scale, objects: list)
                        let expected = (32 * 2 * scenario.size / scale, 16 * 2 * scenario.size / scale)
                        guard (image.width, image.height) == expected else { throw H4Error.malformed("size \(image.width)×\(image.height), expected \(expected)") }
                        let name = outDir.appendingPathComponent("\(stem).L\(level).png")
                        try image.pngData().write(to: name)
                        rendered += 1
                        print("\(rel)\tL\(level)\t\(image.width)×\(image.height)")
                    } catch {
                        failed += 1
                        print("\(rel)\tL\(level)\tFAIL \(error)")
                    }
                }
            } catch {
                failed += 1
                print("\(rel)\tFAIL \(error)")
            }
        }
        print("# rendered \(rendered)/\(levels) levels, missing textures \(compositor.missingTextures.count), missing masks \(compositor.missingMasks.count), missing models \(models.missingModels.count)")
        compositor.missingTextures.sorted().forEach { print("  MISSING texture \($0)") }
        compositor.missingMasks.sorted().forEach { print("  MISSING mask \($0)") }
        models.missingModels.sorted().forEach { print("  MISSING model \($0)") }
        if failed > 0 || rendered != levels || !compositor.missingTextures.isEmpty || !compositor.missingMasks.isEmpty
            || !models.missingModels.isEmpty { exit(2) }

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
