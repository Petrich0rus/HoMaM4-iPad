# Plan — Step 4 "Combat" (program step 4 of 7) — rev 1, 2026-11-02

Envelope: the program envelope of PLAN-step1.md applies, with the amendments of steps 2 and 3 (exe numeric/rule tables may be
embedded in git annotated [D] with their exe address; stats and costs that exist in Data tables are read at runtime; no game
material in git; logic in H4Kit; fidelity + [I] marking for inferred rules).

AMENDMENT (user decision 2026-11-02, "go faster, test in bulk later"):
- Engine slices (rules: 9a, 9d) keep a frozen Python reference and byte-identical logs: they are what catches silent regressions.
- Render and app slices (9c, 9e) are accepted on: H4Kit builds, `swift test` green, H4App builds, a short manual check in the
  simulator. Pixel oracles, AutoCombat over the 105 maps and the independent verifier are deferred to a bulk test (one pass
  for several slices), listed in the README under "Deferred to the bulk test".
- Work split: discovery (Ghidra on heroes4.exe, data dumps, references) runs in a local Claude Code session on the Mac, which is
  the only place with the game data and REA/Ghidra. Its outputs that contain no game material (SPEC.md, *.py references,
  [D] tables, hashes) are committed under `H4Kit/Research/step4/`. Swift implementation can run in a cloud session (no Swift
  toolchain there: the Mac compiles, `swift build && swift test` + Xcode build after each slice).

Base: step 3 done (8a 9e243d9, 8b 87cd61f, 8c 89cae14 on branch claude/great-volta-u9s7zg).
Already available: `H4CombatObject` (combat_object.*, reader 0x606eb0: footprint, elevation, sprite), creature table at runtime
(`table.creatures`: keyword, level, alignment, experience, growth, cost, names), actor sequences (`H4ActorSequence`), MSVC rand,
armies and heroes in the session (7a/7b/8a), towns and garrisons (8a).

Outcome of step 4: on the adventure map, moving an army onto a hostile army (neutral monsters or an enemy player's army) starts
a tactical battle instead of being refused. The battle screen shows the battlefield of the terrain, its obstacles and both armies
(creature stacks and heroes as units). The human player commands its units turn by turn (move, melee attack, ranged attack,
wait, defend); the other side is played by a minimal [I] combat AI (replaced in step 6). Damage, retaliation, turn order and
the end of battle follow the game's rules. After the battle the result is applied on the map: losses, the defeated army removed,
experience to the winner's heroes, the attacker standing on the battle cell or retreating.
Non-goals step 4: spells and magic in combat, hero abilities and skills beyond base stats, creature special abilities beyond
what the discovery classifies as "core" (listed in SPEC), sieges (town walls, towers, gates), surrender and retreat costs,
quick-combat (auto-resolve) — unless discovery shows it is a cheap reuse of 9a with the AI on both sides —, morale/luck if not
decoded (then [I] off), combat sounds/music, original combat interface art.

Dependencies: 9-D → 9a → (9b, 9c in parallel) → 9d → 9e.

## Slices

### 9-D — Discovery (local session on the Mac, Ghidra + data)
Output (committed, text only) in `H4Kit/Research/step4/`:
- `SPEC.md`: with exe addresses for every rule, sections
  1. battlefield: grid size and shape, cell coordinates, obstacle placement (combat_object choice by terrain, rand calls),
     deployment cells of attacker/defender, unit footprints (1x1 / 2x2), elevation if it matters to the rules;
  2. units: which creature stats come from `table.creatures` (columns: attack, defense, damage min/max, hit points, speed,
     movement, shots, …) and which from the exe; hero as a combat unit (base stats by class/level); stack size;
  3. turn order: initiative/speed, ties, wait queue, new round, morale (extra/lost turn) and luck if decoded;
  4. movement: reachable cells, cost, flying, blocking, zone of control if any;
  5. attacks: melee adjacency, ranged rules (shots, range penalty, obstacle penalty, adjacent-enemy rule), damage formula with
     every constant and rounding step, retaliation (once per round?), first strike etc. only if "core";
  6. end of battle: conditions, casualties, experience formula, what happens to the loser (army removed, hero fate);
  7. rand(): every call site in order (damage roll, morale, luck, obstacles);
  8. core creature abilities: the list kept for step 4 (e.g. flying, ranged, no retaliation, double attack), others deferred;
  9. graphics needed by 9c: battlefield background resource per terrain, obstacle sprites, combat actor sequences per creature
     (names, directions, actions: wait, walk, melee, ranged, hit, death), hero combat actors, projection grid ↔ screen.
- `combat_ref.py`: FROZEN Python reference (sha256 in SPEC) running a battle from a JSON setup (two armies, terrain, seed) and a
  JSON command list for the human side, with the [I] AI for the other side, printing a canonical JSON log (one record per action:
  unit, action, target, rolls, damage, kills, retaliation, round, end). Docstring rules R1…Rn are normative.
- Oracle: 10 to 20 battles (setups + scripts + logs) covering every rule above, incl. ranged, flying, 2x2 units, ties, morale
  and luck if decoded, both outcomes; `ORACLE.sha256`.
- `[D]` tables extracted from the exe (as Swift-ready text) with their addresses.
Stop: a rule cannot be decoded → mark it [?], choose an [I] rule with the user, never guess silently.

### 9a — Combat rules (H4Kit, headless) — depends on 9-D
Scope: new `H4Combat.swift` (battle state, units, turn order, movement, attacks, damage, retaliation, end), `H4CombatAI.swift`
(the [I] AI of the reference), additions to `H4GameTables.swift` (combat stats from table.creatures), tests `H4CombatTests.swift`;
h4tool `combat <Data> --setup s.json --script c.json --out log.json`. No change to existing behaviour.
Acceptance: K1 `h4tool combat` byte-identical to every oracle log; K2 unit tests on hand examples of the damage formula,
turn order ties and the end conditions; K3 `swift test` green, H4Kit iOS build.

### 9b — Battlefield setup from the adventure map (H4Kit, headless) — depends on 9a
Scope: build the 9a setup from the session (attacking army, defending army or neutral stack incl. stack splitting rules if
decoded, terrain of the battle cell, seed) — `H4CombatSetup.swift`; h4tool `combat-setup <Data> <maps-dir> <map> --script s.json`.
Acceptance: setups equal the reference setups of the oracle battles that start from a map (if the discovery provides them),
else [I] documented; `swift test` green.

### 9c — Battle rendering (H4Kit) — depends on 9a; lighter acceptance (amendment)
Scope: `H4CombatRender.swift`: battlefield background for the terrain, obstacles, units (combat actor sequences, facing,
current action frame), selection and reachable-cell overlays, projection cell ↔ pixel and hit-test (cell under a point).
Acceptance: builds, unit tests on projection/hit-test round trips, h4tool `combat-scene` renders a PNG; visual check by the user.

### 9d — Combat in the game session (H4Kit, headless) — depends on 9a, 9b
Scope: `H4GameSession` (v3 ruleset, v2 unchanged): moving onto a hostile army starts a battle (instead of the refusal); session
commands `battle-move`, `battle-attack`, `battle-shoot`, `battle-wait`, `battle-defend` through `execute(command:)`; on end, the
result is applied (losses, army removed, experience, attacker position); log schema extended. h4tool `play --ruleset v3`.
Acceptance: L1 `--ruleset v2` and `v1` logs unchanged (8a T1–T3); L2 v3 scripts byte-identical to the reference session logs
(reference = 8a session2_ref + combat_ref); `swift test` green.

### 9e — Battle screen in the app (H4App) — depends on 9c, 9d; lighter acceptance (amendment)
Scope: `CombatScreen.swift` + `CombatModel.swift`: full screen opened when 9d starts a battle; tap own active unit's target cell
= move, tap enemy = melee (move + attack) or shoot when ranged, buttons Wait / Defend, long press = unit info (stats, count,
hit points); AI turns animated; end of battle panel (losses, experience) then back to the map, map updated. Every state change
through `session.execute(command:)` (single mutation path, as 8c). DEBUG: `-H4AutoCombat` (deferred to the bulk test).
Acceptance: H4App builds, manual check of one battle against neutrals in the simulator.

## Deferred to the bulk test (all steps)
8c C2–C4 (scripts in the simulator, screenshots, AutoTown over 105 maps); 9c pixel checks; 9e AutoCombat; deletion markers
(Editor.Bomb) not modelled at game start and still drawn by the static map viewer; minimap magenta terrain colours.

Open [?] items carried from step 3: hero hire price, mage guild contents, neutral garrison growth, month events, generic growth
bonus FUN_00416240, vcall(5)+25% term, weekly generator 50% roll, random default dwelling, town terrain choice details.
