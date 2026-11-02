# H4Kit

Swift reader for the resource archives (`.h4r`) of *Heroes of Might and Magic IV*.
It is the first building block of a future iPadOS port. The library ships no game files:
it reads the player's own copy (GOG version, `Data` folder).

Platforms: iPadOS 17+, macOS 14+. No dependencies (gzip goes through Apple's `Compression` framework).

## Usage

```swift
let store = try H4ResourceStore(dataDirectory: dataURL)   // opens the 9 archives in the game's order
let bytes = try store.data(for: "layers.button.cancel.h4d")
```

Command-line tool:

```bash
swift build -c release
.build/release/h4tool summary <Data>
.build/release/h4tool verify  <Data>
.build/release/h4tool extract <Data> <out> [prefix]   # e.g. prefix "strings."
```

## Format (reconstructed from the files)

| Field | Type |
|---|---|
| signature | `"H4R" 0x05` |
| directory offset | u32 (8 in most archives, at the end in `text.h4r`) |
| entry count | u32, at the directory offset |
| per entry | u32 offset, u32 stored size, u32 real size, u32 Unix date, then 3 strings (u16 length + bytes): name, original path, alias target, then u32 storage (1 = raw, 3 = gzip) |

- **Aliases**: a non-empty target string means the entry reuses the data of another resource,
  possibly located in a different archive.
- **Names** are compared case-insensitively (4 aliases in the game only resolve that way).
- **Load order** (strings in `heroes4.exe`): heroes4, storm, x2, movies, music, text, updates,
  storm_override, storm_updates, x2_override, x2_updates, new. Here the last one in the list wins.
  Confirmed with REA/Ghidra 12.1.4: the game opens these archives in reverse order, and its
  registration function (`0x7ff930`) only adds an entry if the name is not yet known
  (lookup `FUN_00800180`). The first archive opened wins, which gives the same result.
  Case-insensitivity on the game side is not yet verified.
- Known defect in the original data: the alias `layers.sample_cursor.h4d` points to a resource that does not exist.

## Status (HoMM4 Complete, GOG)

9 archives, 21,338 entries, 19,928 unique resources; 20,694 payloads (1.7 GB) decompressed
with size and CRC32 checks in about 7 s.

## Images (slice 2)

```swift
let group = try H4LayerGroup(data: store.data(for: "layers.button.cancel.h4d"))
let png = try group.layer(named: "Released")!.rgba().pngData()
let walk = try H4ActorSequence(data: store.data(for: "actor_sequence.archdevil.walk.e.h4d"))
```

```bash
.build/release/h4tool png <Data> "animation.spell.fire shield.h4d" <out>   # one PNG per frame
.build/release/h4tool decode-all <Data>
```

Formats reconstructed with REA/Ghidra from `heroes4.exe` (layer reader `0x595880`,
group reader `0x58e2e0`), then validated on every file in the game:

| Type | Structure | Game files |
|---|---|---|
| `layers` | u16 count + layers (UI screens, buttons, cursors) | 781 (9,824 images) |
| layer | 256-colour **BGR** palette, name, rectangle, one span per row, 1 byte per pixel, 4-bit alpha if type ≥ 4 | 150,251 layers |
| `animation` | group + frame duration (ms) + frame order (+ hotspot in v2) | 325 (4,862 frames) |
| `actor_sequence` | header (type 2 or 3) + frames + anchor point + metadata | 13,336 (135,565 frames) |
| `bitmap_raw` | 16-byte header + BGR 24-bit, top row first | 3 (main menus) |

Not decoded yet: the `actor_sequence` metadata tail and the two flags of the v2 animation block.

## Terrain, objects, fonts (slice 3)

```swift
let grass = try H4TerrainTexture(data: store.data(for: "terrain.grass.2.1.h4d"))   // 100 tiles of 64×32
let sphinx = try H4AdventureObject(data: store.data(for: "adv_object.power ups.Sphinx.h4d"))
let font = try H4Font(data: store.data(for: "font.Prose_Antique.36.h4d"))
let title = font.render(text: "Héros IV")
```

```bash
.build/release/h4tool text <Data> font.Prose_Antique.36.h4d "Héros IV" title.png
```

| Type | Structure (readers in `heroes4.exe`) | Files |
|---|---|---|
| `terrain` | 100 isometric 64×32 tiles stored **by column**, runs (gap, count, indices), BGR palette — `0x797260` | 61 (6,100 tiles) |
| `adv_object` | v1–6: type, footprint W×H in tiles, bit grids (blocked cells, edges), classification (id + name), then a sprite (frames + anchor) and, for type-0 images, one depth per 32-px column — `0x44d860` | 2,798 |
| `combat_object` | v0/2: footprint, elevation, frames/second, 5 properties, type + name, then the same sprite — `0x606eb0` | 1,048 |
| `font` | 225 glyphs: width, height, spacing before/after, 1 byte/pixel (high nibble letter, low nibble shadow) — `0x71bee0` | 21 |

Inferred and still to confirm: the names of the three size bytes of a font, and the
meaning of the second and third object bit grids (probably passability of edges), along
with the three values of sprite version 3.

## Maps (slice 4)

```swift
let scenario = try H4Scenario(fileData: Data(contentsOf: mapURL))       // header: name, size, players…
let terrain = try H4ScenarioTerrain(scenario: scenario)                 // tiles + heights, per level
```

```bash
.build/release/h4tool maps <maps-dir>                                  # 85 scenarios
.build/release/h4tool minimap <Data> "<maps>/A Land without a King.h4c" king
```

- **Container** `.h4c`: `"H4CAMPAIGN"`, version 21–22, single-scenario/campaign byte, then gzip.
- **Header** (reader `0x77a420`): version 20–29, size, levels, players (colour, human, alignments),
  name, difficulty, description, teams, texts. 85/85 read (versions 27 and 29).
- **Body** (loader `0x4d12d0`): ~15 sections, then **objects** (each with its own serializer, without
  a length → not decoded yet), then **terrain**, then the corner heights that end the file.
- **Terrain located without the objects**: the size of the height grid is known (diamond
  geometry transcribed from `0x74dcf0` / `0x74e010`), so the end of the terrain is known; its start
  is the offset from which all tiles decode with values accepted by the game (`0x413b30`)
  and land exactly on that end. Single-pass search (85 maps in ~1 s). Found on **85/85 maps**,
  unique on 82. On the remaining 3, a second offset also decodes (13 to 72 tiles differ): the
  reading whose flags match the map's dominant value is kept, then the one that best agrees
  with its neighbours. Maps larger than 320 (the largest shipped is 304) are refused.
- Terrain types: 0 water, 1 grass, 2 rough, 3 swamp, 4 lava, 5 snow, 6 sand, 7 dirt,
  8 subterranean (2 variants each); 9–18 still to identify (< 1 % of tiles).

Not done yet (slice 4): identification of types 9–18, textured rendering with transitions,
multi-map campaigns.

## Objects (slice 5)

```swift
let store = try H4ResourceStore(dataDirectory: dataURL)
let body = try H4ScenarioBody(scenario: scenario, resources: store)   // sections + scripts + objects
```

```bash
.build/release/h4tool objects    <Data> <maps-dir> [--histogram]   # 105 maps, recursive
.build/release/h4tool check-body <Data> <maps-dir>                 # object end == terrain start?
```

**Result: on the 105 shipped maps (85 in `maps/`, 20 in `maps/Contest Maps/`), every object is
decoded and the list ends exactly where the terrain starts** (an independent check: the terrain
start is located from the end of the file, slice 4). Output identical byte for byte to an
independent Python implementation (`Research/`).

- **Header**: from version 24, victory/defeat each carry a cinematic block (text, movie, name).
- **Sections before the objects** (`H4ScenarioSections`): lists of events, 12 availability blocks,
  per-player settings, bitsets and id lists (readers `0x4cfa90`…`0x85e790`).
- **Scripts** (`H4ScenarioScripts`): tree grammar read from the exe, 54 actions, 21 numeric
  expressions, 24 conditions; events (triggered, timed, continuous).
- **Object list** (`0x4ced20`): u32 count, then per object i32 x, y, level, u8 flag. Flag 0 = named object
  (model name, classification triple, then the class's own data, vtable +0x90), otherwise an army.
  No length is stored: every one of the 105 classes has its reader; an unknown class stops cleanly.
- **Class** resolved by name from the model's `adv_object` resource, as the game does (`0x7c7ca0`); the
  triple in the file must match.
- Families: ~75 "version only" classes, portals/events, signs, lighthouses/shipyards, armies and heroes
  (`H4ScenarioArmies`), towns, mines/garrisons, dwellings, generators, quests, schools, shrines,
  prisons… (`H4ScenarioObjectData`).
- Fields whose meaning is not yet known keep neutral names (`field6A0`, …). Inferred from the data and
  not from the exe: the "artifact"/"material" payloads of the availability blocks (any other type is refused).
- Known gaps from the verification (minor): a few checks differ slightly from the game's (expression version
  ≤ 2 required, unknown placement kind refused, player colour and portrait bound not checked); some
  readers (carry-over hero, random conservatory, old town versions) are not exercised by any shipped map.

Not done yet: identification of terrain types 9–18, textured rendering, multi-map
campaigns, scenario versions other than 27/29.

## Map rendering (step 1)

```bash
.build/release/h4tool render     <Data> <map.h4c> out.png [--level L] [--cells r0 c0 nr nc] [--scale 1|2|4|8]
.build/release/h4tool render-all <Data> <maps-dir> <outdir> [--scale k]     # 105 maps, ~10 s at scale 4
```

- **Terrain** (`H4MapTerrainRender`, `H4TerrainCompositor`, `H4TransitionLibrary`): base tile chosen from a
  random window of the texture per 4×4-cell chunk (deterministic function, not bit-exact with the game), transitions
  (`transition.Transitions.h4d`: 15 sets × 93 masks, 1 or 4 bits per pixel) and roads. Identical pixel for pixel
  to the Python reference (`Research/`) on the test areas.
- **Objects** (`H4MapObjectRender`): sprite anchored on the top vertex of the object's cell (x = row, y = column),
  shadows first, then 32-px vertical strips sorted by depth (one depth per sprite column, `adv_object`
  table), ground objects (bridges, fields) underneath; frame 1 of the animation. Identical to the Python reference.
- Known gaps: the magic terrains (12–14) use a different tile layout; road "kind 3" and the road
  sub-variant are inferred; not drawn yet: armies/heroes, owner flags, animation; the editor's markers
  for random objects ("Ville", "Monstre"…) appear as they are (replaced when a game starts).
- Images produced from the game stay outside the repository (`out/` is ignored).

## iPad map screen (step 1, H4App)

- Opening a map from the list: the static map (terrain + objects) is drawn by the H4Kit renderer in
  512-px tiles (`CATiledLayer`, `UIScrollView`): scrolling with inertia, pinch zoom (whole map → 2×), double tap,
  surface/underground toggle, long press → card (cell, terrain, object and its class).
- The renderer is thread-safe (one lock around the caches; parallel drawing), tested under Thread Sanitizer.
- DEBUG test `-H4AutoTour`: opens the 166 levels of the 105 maps one after another (whole view then 1:1),
  logs `TOUR ok/fail/done` and the time per tile; ~36 ms median per tile, ~130 MB of memory in the simulator.
- Known limits: double tap never driven by a tool; zoomed-out tiles slower (0.2–0.6 s) on large
  maps; a single memory crash seen once (attributed to clearing the tile layer while it was drawing, removed since;
  4 clean full runs since then); performance on a real iPad not measured.

## Starting a game and moving around (step 2)

```bash
.build/release/h4tool gamestart <Data> <map.h4c> --seed N --difficulty D     # random objects resolved
.build/release/h4tool moves     <Data> <maps-dir> --queries q.json --out a.json
.build/release/h4tool towns     <Data> <maps-dir> --out t.json
```

- **Starting a game** (`H4Game`, `H4GameStart`): the game's MSVC random generator, every random object
  (towns, monsters and their size by difficulty, dwellings, artifacts, resources, shrines, teachers…)
  resolved as the exe does; identical to the Python reference on 105 maps × several seeds and difficulties.
  The stats come from the `table.*` tables of the player's data; only identifier name tables from the exe
  are in the code. Not yet: starting resources, starting hero for a player without one, the
  editor's deletion markers ("Editor.Bomb", likely deletes the object underneath at game start).
- **Movement** (`H4Movement`): passable cells, object entrances (edges), costs per terrain (grass 100,
  swamp 200, snow 175…), roads 75/100, diagonals ×1.5, 2256 points per day, path search (Dijkstra in the
  exe's order), split into days. Identical to the reference on 2,836 trips; ~0.7 ms for a trip across a
  304 map. Not yet: boats, skills (Pathfinding…), artifacts, path arrows.
- **Started game** (`H4GameRender`, `h4tool render --game --seed N --difficulty D`): random objects drawn with
  their real model, armies and heroes (animated `adv_actor` sprite, frame 1, facing south-east),
  boats, owner flags (`animation.Flags.<colour>`, gray for neutral) on owned buildings and on heroes; the
  editor's markers (bomb, events, obelisk markers) are hidden. Identical to the Python reference on 10 areas.
- **Playing a turn** (`H4GameSession`, `h4tool play`): hot-seat human players, calendar (day/week/month),
  army selection, path planned with arrows (green today, red after), move limited to today's points,
  pickups (resources, artifacts, chests, campfires — amounts inferred, documented), end of turn. Identical to
  the Python reference on 10 scenarios (more than 600 commands).

## Towns, economy and building rules (step 3, slice 8a)

```bash
.build/release/h4tool play       <Data> <maps-dir> <map-name> --script s.json [--out log.json] [--ruleset v2|v1]
.build/release/h4tool towns-init <Data> <maps-dir> [--out t.json]
```

- **Session v2** (`H4GameSession(..., ruleset: .v2)`, `h4tool play`, default): starting resources by team and difficulty, towns
  (`H4Town.swift`: state, build / recruit / transfer, visiting hero, day tick) and economy (`H4GameEconomy.swift`: town and mine income,
  creature growth, Order treasury, weekly generators, peasants, computer-player bonus). Commands `build`, `recruit`, `transfer`; every log
  record gains `towns`, `armies`, `gens` (move records `visited`). `--ruleset v1` / the default of the Swift API is the frozen 7d-L session.
- Identical byte for byte to the frozen reference `session2_ref.py` on 9 town / economy scripts, the 5 step-2 scripts re-run under v2, and
  (v1) the 5 frozen step-2 logs; `towns-init` reproduces the initial state of the 657 towns of the 105 maps.
- Costs of buildings come from `table.buildings` (runtime parser `H4BuildingTable`), growth and creature costs from `table.creatures`. The
  tables that exist only in the executable are embedded with their address (`// [D] exe 0x...`): requirement trees (0xacfbe0), static
  buildable sets (0xacfbb0), building keywords (0x97dcf8...), dwelling creatures (0x9853d0), starting resources (0x98e9e8), mine incomes
  (0x98cbb8), generator pots (0x997ff0), computer multipliers (0x979acc, 0x979b60), treasury rate (0xacffe8).
- Inferred / pinned [I] as in the reference: default-built dwelling count and no `rand`, the other-might-grail growth bonus (+25), hero-skill
  term 0, generators pay on their first tick without the 50 % roll, `allowed` used as an extra filter, visiting rules, taxpayers after pass B.

## Town screen rendering (step 3, slice 8b)

```swift
let renderer = H4TownRenderer(store: store)
let (image, drawList) = try renderer.render(faction: 0, background: "snow", built: [0, 3, 8, 9, 12])   // 1280x825 RGBA, scale 1
let hits = try renderer.hitTest(faction: 0, background: "snow", built: [0, 3, 8, 9, 12], points: [(x: 527, y: 785)])
```

```bash
.build/release/h4tool town-scene        <Data> --fac life --terrain 5 --built 0,3,8,9 --out scene.png [--draw draw.json]   # or --bg <name>
.build/release/h4tool town-hits         <Data> --fac life --terrain 5 --built 0,3,8,9 --points pts.json --out hits.json
.build/release/h4tool town-terrain-all  <Data> <maps-dir> --out towns_terrain.json    # 657 towns
.build/release/h4tool town-check-all    <Data> <maps-dir> --out missing.json
.build/release/h4tool town-thumbs-all   <Data> --out thumbs.json
```

- `H4TownRender.terrain(...)`: terrain id of a town [D 0x894bc0]: the terrain of the entrance cell (first edge bit of the model's footprint,
  `(X + i + 1, Y + j)`), else the nearest footprint cell with terrain 1...8 (last of equal minima). Background name from the table at 0x8ab0d0
  (`H4TownRender.backgroundName`): 0 sand, 1...8 grass, rough, swamp, volcanic, snow, sand, dirt, subterranean, 9 sand, 10 volcanic, 11 snow,
  12...18 grass (`layers.town.chaos.volcano` is never used).
- Scene: background layer, shadows, buildings (animated ones = `base` + first frame of the playback order, else the layout layer), then the
  foreground layers. Only the highest hall / keep / mage guild is drawn; ids that are no building of the faction are ignored. Buildings and
  shadows are sorted by the bottom edge of their layout layer, then by id [I]. Compositing is `H4Layer.draw`.
- Hit-test [I]: topmost displayed building with alpha > 0 under the point; shadows and foregrounds are not clickable. The answer carries the
  whole stack, topmost first. Build-dialog thumbnails: the layer of `layers.town.<fac>.thumbnails` named like the building keyword.
- Identical to the frozen reference `town_ref.py` on the 12 oracle scenes (pixels and draw lists), the 30 hit-test points, the terrain id and
  background of the 657 towns, the check of every town's layers (0 missing) and the thumbnail table. About 0.1 s per scene in release,
  including opening the archives and encoding the PNG. The scene scale of the window (client width * 0.00078125) is left to the app.

## Playing on iPad (step 2, H4App)

"New game" on a map's page (difficulty, seed): game screen with a SwiftUI bar (day/week/month, colour of the
player, 7 resources, card for the selected army, End turn). Tap your army = select (ring on the ground),
tap a cell = path with arrows, tap again = the hero walks (animation, camera follows), pickups, end of turn.
Only the tiles that change are redrawn. DEBUG: `-H4AutoPlay` plays one pickup on every map (97 ok, 8 skips
with a reason, 0 failures), `-H4GameScript` replays commands.
Known limits (follow-ups): no combat/AI/towns/fog yet, interface not yet the original artwork, starting resources
and some amounts provisional, ~1 s per move on very large maps (draw list rebuilt on the main thread),
pixel boxes read through `Mirror` (to replace with a public API), overlay to stop if the screen is closed mid-walk.
