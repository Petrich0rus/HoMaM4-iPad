# Plan — HoMM4 map objects (slice 5, in waves)

## Program envelope
Goal: decode the full scenario body of the 105 shipped `.h4c` maps in H4Kit: the sections before the objects, then every object record, so that the last object ends exactly where the terrain starts (`H4ScenarioTerrain.start`, already located independently in slice 4).

Map population (all waves): `maps/**/*.h4c` recursive = 105 files (85 top-level + 20 in `maps/Contest Maps/`). `h4tool maps`/`objects` enumerate recursively. Today 103/105 headers read; the 2 others ("Seven Steps To Glory", "The Four Horsemen") carry header victory/defeat scripts: excluded from 5a by name, handled in 5d. All python baselines (parse_sections.py, chain.py/allmaps.py) are re-run over exactly this population before comparison (baseline changes: see 5a step 0).

Shared constraints
- Swift package `REA/H4Kit` (lib H4Kit + h4tool + tests). iOS 17 / macOS 14, no dependencies, no game assets in the repo or tests (real-data tests only when `H4_DATA_DIR` / maps dir env is set).
- Formats are taken from heroes4.exe (REA/Ghidra + objdump), every reader cites its exe address. Carve-out: layouts that could only be inferred from the data (5a: the script-expression node payloads, 42 node names; table at 0xa8d8c8 not decompiled) are allowed only if (a) marked "inferred from data" in code and README, (b) validated on the whole population, (c) failing closed (explicit error) on any unknown node name; versions 27 and 29 supported (all shipped maps), other versions rejected with a clear error.
- Never guess past unknown bytes: no length prefix exists, so an unsupported class stops the object parse with an explicit "stopped at class X, offset N" result rather than a skip. Parsing hostile/truncated files must throw, never crash or allocate unboundedly (counts capped).
- The game's own validity checks (version values, ranges) are reproduced as validation.
- Evidence inputs: scratchpad `sections/SPEC.md` + `parse_sections.py` (historical baseline: 85 top-level maps only; Contest Maps never checked for sections = known risk), `objects/SPEC.md` (framing, class table of 105 slots, simple readers) + `allmaps.py` harness.
- Each wave: build, tests, real-data run on the 105-map population, then fresh `verifier`. README + memory updated. No git, nothing committed (folder is not a repo).

Waves (each independently approvable)
- 5a Sections + object framing + simple classes (this slice).
- 5b Towns + random towns (readers 0x89a710, 0x7f52b0).
- 5c Armies: `t_army` 0x523a30, shared army reader 0x640d00, ownable/garrison family (0x7d3f60, 0x7d2fd0, 0x7d4150, 0x7d4390, 0x7d45c0, script objects 0x7d3530): garrison, mine, abandoned_mine, dwellings, random_monster.
- 5d Quests (0x7eec70, 0x7ef7e0, 0x7efac0) and the remaining small classes; final acceptance: 105/105 maps parse (header scripts included) every object and end exactly at the terrain start.
Rollback for every wave (folder is not a git repo): before the first edit, copy every existing file the wave modifies to `scratchpad/snapshot-<wave>/` and record the pre-wave `swift test` result. Rollback = restore those copies + delete the wave's new files; acceptance of rollback = `swift test` identical to the pre-wave run.
Existing files modified by 5a: `Sources/H4Kit/H4Scenario.swift` (header scripts), `Sources/H4Kit/H4Error.swift` (only if a new case is needed), `Sources/h4tool/main.swift` (command `objects`, recursive enumeration), `README.md`. Later waves: `H4ScenarioObjects.swift` (+ new files per family), README.

## Slice 5a — sections + framing + simple classes
Outcome: `H4ScenarioBody(scenario:)` returns the pre-object sections, the object-list start, the declared object count, and the list of objects decoded up to the first unsupported class.

Step 0 (main session, before any Swift edit) — baselines over the population: parse_sections.py gets a recursive glob and lists the 2 excluded maps by name; chain.py/allmaps.py stop on artifact subclasses parchment (124) / scroll (166) (spell_artifact, reader 0x430e10) and compare the file triple by name with the adv_object resource triple, reporting mismatches. If real triple mismatches appear, the slice pauses and the rule is brought back to the user (no silent workaround).

Scope (new files `Sources/H4Kit/H4ScenarioSections.swift`, `H4ScenarioObjects.swift`, tests `Tests/H4KitTests/H4ScenarioObjectsTests.swift`; h4tool new command `objects`):
1. Sections (per sections/SPEC.md): lists A/B/C/D with the script-expression node grammar (42 node names inferred and validated on data; unknown node name → explicit error), 12 availability blocks ("artifact"/"material" payloads; other type names → error), player block, bitsets, flags, id/value lists. Expose them as raw typed structs (semantic names only where established).
2. Object framing: u32 count (cap 100 000), per record i32 x, y, level, u8 flag; flag 0 → str16 model name + (version ≥ 14) classification triple (u16 0, 3 × (u16 id, str16)) + class payload; flag ≠ 0 → army (unsupported in 5a → stop).
3. Class resolution, as the game does (FUN_007c7ca0 + FUN_004cf190): the class comes from the **model name via its `adv_object.<model>.h4d` resource** (H4AdventureObject classification triple, read from the player's data through `H4ResourceStore`; API `H4ScenarioBody(scenario:, resources:)`). Class names → class enum (105 slots, FUN_00463630); subclass overrides (table 0xac08e0, objects/SPEC.md §3) resolved by class+subclass name. The file's own triple is then compared by name with the resource triple; a mismatch, or a missing resource, is an error (game behaviour). Any (class, subclass) whose registered reader is not implemented — notably the artifact subclasses mapped to spell_artifact (reader 0x430e10) — stops the parse as unsupported; nothing is read as version-only unless its resolved reader is 0x4fa760.
   Header victory/defeat scripts: NOT in 5a (non-goal, moved to 5d). Fixed exclusion set for 5a = {"Seven Steps To Glory", "The Four Horsemen"} (header refused, as today).
4. Readers for: version-only classes (0x4fa760, u16 == 0), gateway/event family (0x44a750) and sign/ocean_bottle (0x46ddb0), obelisk_marker (0x7c6a80), outpost (0x8a1260), owned-scriptable header (0x478a10: lighthouse, shipyard, windmill) with script count 0 only (n > 0 → stop as unsupported).
5. h4tool `objects <maps-dir>`: per map — object start, count, decoded count, stop class/offset, class histogram.

Non-goals: towns, armies, mines/garrisons/dwellings, quests, script semantics, rendering of objects, multi-map campaigns, scenario versions other than 27/29.

Acceptance
- A0 Headers: exactly 103/105 read; the 2 failures are exactly the named exclusion set.
- A1 Sections: on every map whose header reads the computed object-list start equals `parse_sections.py`'s offset and the count matches.
- A2 Framing: on the 103 maps, records decode without desync up to the first unsupported class; stop class, stop offset and decoded count equal the updated python harness on every map (0 differences).
- A2b Class check: for every decoded record the Swift-resolved class equals the harness's resource-resolved class (0 mismatches); file-vs-resource triple mismatches are 0 in both (otherwise pause, see step 0); h4tool reports the spell_artifact records met and each one stops the parse.
- A3 Any map whose objects are all supported ends exactly at `H4ScenarioTerrain.start` (report how many — possibly 0 in 5a).
- A4 Hostile inputs: truncated bodies, huge counts, unknown class/node names, bad versions → H4Error thrown, test runs fast (< 1 s), no crash.
- A5 `swift test` all green (existing 44 + new), `swift build` for iOS succeeds, 105 maps processed by h4tool in a few seconds.
- A6 README section "Objects (slice 5a)" + memory updated.
Verification: fresh `verifier` reproduces A1–A5 independently.
