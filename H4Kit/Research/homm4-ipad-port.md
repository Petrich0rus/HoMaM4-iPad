---
name: homm4-ipad-port
description: "HoMM4 → iPadOS port project in REA folder: approach, slices, where things are, REA blocker"
metadata:
  node_type: memory
  type: project
  originSessionId: b0a8b84f-1fe9-498d-b633-5bb45dbda9c4
  modified: 2026-10-30T19:30:15.966Z
---

Goal (started 2026-10-30): turn Heroes of Might and Magic IV into an iPadOS app using REA (reverse-engineering MCP).
Source: `REA/Heroes of might and magic IV.dmg` = GOG Windows version (heroes4.exe PE32 x86) in a Wineskin wrapper; game data in `.../drive_c/GOG Games/HoMM 4 Complete/Data/*.h4r` (game is in French).

Approach chosen by user: engine reimplementation in Swift/Metal (VCMI-style), app loads user's own GOG data, ships no game assets. Emulation on iPad ruled out (no JIT).

Slices: 1 = `.h4r` archive reader → done in `REA/H4Kit` (Swift package, lib + `h4tool`, verified). 2 = images → done 2026-10-30 (`H4Image.swift`: layers, animation, actor_sequence, bitmap_raw; palettes are BGR; formats from exe reader 0x595880 / group 0x58e2e0; all 14,445 image resources decode; verifier matched 1,052/1,052 layers pixel-exact; blend overflow fixed). 3 = world resources → done 2026-10-30 (`H4World.swift`: terrain = 100 tiles 64×32 stored by column, readers 0x797260/0x797050; adv_object 0x44d860; combat_object 0x606eb0; font 0x71bee0; all files exact). 4 = maps (partial) → 2026-10-30 (`H4Scenario.swift` header 85/85; `H4ScenarioTerrain.swift` terrain located from file end without parsing objects — objects have no length prefix, ~100 serializer classes; linear single-pass search, unique on 82/85, tie-break dominant flags then neighbour agreement on 3; road kind < 4 check; size cap 320; verified). 5 = objects DONE + verified 2026-10-31: all 105 maps (85 + maps/Contest Maps) decode header, sections, exe-decoded script grammar and every object (105 classes); object end == terrain start on 105/105 (`h4tool check-body`), `h4tool objects` byte-identical to python reference. Specs + python reference saved in `H4Kit/Research/` (no game data). Minor known gaps (P3/P4) listed in README. Work was finished partly in a forked session that also started `REA/H4App` (iPad shell) and render discovery. User chose terrain-first; next options: objects in waves (decorative first), terrain types 9–18, textured render, iPad map viewer.

Update 2026-10-31: USER GOAL = the FULL game incl. both expansions (Gathering Storm, Winds of War), not just a map viewer. Roadmap: 1 read maps fully (waves 5a–5d), 2 Metal adventure-map render in iPad app REA/H4App, 3 adventure rules, 4 towns, 5 tactical combat, 6 AI, 7 saves/campaigns/menus/audio. User gave carte blanche / AUTO (no commit/push/install), test rendering in iPad simulator. 5a done+verified (H4ScenarioSections.swift, H4ScenarioObjects.swift; 105 maps incl. maps/Contest Maps; 97 parse sections, 6 contest maps fail on unknown script nodes, 2 on header scripts). Scratchpad of work: /private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad (PLAN-objects.md, COMMON.md, objects/chain.py+probe.py+ext_*.py plug-in readers). Map coords are signed i32.

**Why:** long multi-slice project; context needed across sessions.
**How to apply:** continue slice by slice; each slice gets a fresh verifier.

REA setup (fixed 2026-10-30): Ghidra 12.1.4 at `~/ghidra/ghidra_12.1.4_PUBLIC`, arm64 natives built locally with `support/gradle/gradlew buildNatives` and copied into each module's `os/mac_arm_64/` (official zip ships none). `GHIDRA_INSTALL_DIR` in `~/.claude.json` points there. Changing it needs a full app quit (Cmd+Q) — `/mcp` reconnect and session restart reuse the old env. Open heroes4.exe with `provider_id: ghidra`; first analysis takes ~1–2 min (46,240 functions).


Step 1 "see a map" (2026-10-31): 6a-T terrain + 6a-O objects in H4Kit (pixel-exact vs frozen python refs, commits bac3d4f, 1914009), 6b iPad map screen (CATiledLayer tiles from H4Kit compositor, gestures, -H4AutoTour 166/166). Repo: github Petrich0rus/HoMaM4-iPad (public), git root = REA/. Plan file + refs in session scratchpad (PLAN-step1.md). Simulator gotcha: two iPads may be booted — the one with game data is iPad Air 11 (0111E59F…); game data must be a real copy in app Documents/Game (symlinks refused). Next: step 2 (play a turn on the map: random objects resolved at game start, heroes, movement, owner flags, animation).

Step 2 progress (2026-10-31): plan SCRATCH/PLAN-step2.md (7a game start → 7b movement → 7c dynamic rendering → 7d play screen). 7a done (37e93ad), 7b done. Frozen refs in session scratchpad step2/{gamestart,movement}. User decision: name-only identifier tables from the exe may live in code (like VCMI). Open: Editor.Bomb deletion markers (273 in 15 maps) probably delete objects at game start — not modelled.

Step 2 DONE 2026-11-01: 7a 37e93ad, 7b 02aed84, 7c 638a92c, 7d-L cc842cb, 7d-A (play screen) committed after. Playable on iPad simulator: new game, select/plan/move/pickups/end turn, identical to frozen python session refs. Follow-ups: move perf on big maps (~1 s), Mirror for pixel boxes, WalkOverlay leak on close mid-walk, original HUD art, starting resources [?]. Next program steps: 3 towns, 4 combat, 5 rest of objects, 6 AI, 7 saves/campaigns/sound.

User decision 2026-11-01: exe tables of numbers/rules (not only names) may be embedded in git like VCMI configs, annotated with exe addresses; Data-table stats/costs still read at runtime.
Step 3 (towns) 2026-11-01: plan PLAN-step3.md (8a headless rules, 8b town scene render, 8c app town screen). User decision "like VCMI": exe numeric tables may be embedded in git with [D] exe address. 8a DONE, verified CONFIRMED, pushed 9e243d9 (H4Town.swift, H4GameEconomy.swift, play --ruleset v2|v1, towns-init). Deferred: P3 float/oversized ints in script commands diverge from python ref; P4 mine subclass map tag [D 0x79c7a0]. Next: 8b (frozen town_ref.py from townscreen scene.py → plan-verifier → execute).
8b DONE 2026-11-02, verified CONFIRMED, pushed 87cd61f (H4TownRender.swift; frozen ref SCRATCH/step3/town8b/town_ref.py b90aa87c; town terrain [D 0x894bc0], bg table [D 0x8ab0d0]; z-order/hit-test/anim fallback [I]). Next: 8c app town screen (needs plan review of 8c slice, then executor).
8c IN PROGRESS (stopped by user 2026-11-02, kept uncommitted in working tree): plan PLAN-step3.md 8c (2 REVISE, fixed; user approved execution). Partial executor work: new H4App AutoTown/ScriptFileRunner/TownModel/TownScreen.swift, H4Kit H4TownQuery.swift + H4TownQueryTests.swift, edits to GameModel/GameScreen/MapBrowserView/MapDetailView/MapSession, H4GameRender/H4GameSession/H4GameTables/H4Town. Not built/verified. Resume: relaunch executor on the 8c contract telling it to continue from the working tree.
