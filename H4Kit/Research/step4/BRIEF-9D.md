# Brief for the local session — slice 9-D (combat discovery)

To paste into a Claude Code session opened in `~/Documents/Claude_Workspace/REA` on the Mac (REA/Ghidra available).

---

Read `H4Kit/Research/PLAN-step4.md` (section 9-D and the amendment) and `H4Kit/Research/homm4-ipad-port.md`.
Work on branch `claude/great-volta-u9s7zg` (git pull first).

Task: slice 9-D only — discover the tactical combat rules of heroes4.exe and produce, in `H4Kit/Research/step4/`:
1. `SPEC.md` with the 9 sections listed in the plan, every rule with its exe address ([D] decoded, [I] inferred, [?] open);
2. `combat_ref.py`, a Python reference that runs a battle from a JSON setup + JSON command list and prints a canonical JSON log,
   with a minimal [I] AI for the non-human side; docstring rules R1…Rn normative;
3. an oracle of 10–20 battles (setups, scripts, logs) covering every rule, with `ORACLE.sha256`;
4. the exe tables as text with their addresses.

Rules:
- Use REA/Ghidra on heroes4.exe (`provider_id: ghidra`) and `H4Kit`/`h4tool` to read the Data tables (table.creatures columns
  for combat stats, combat_object.*, combat actors). Start with the creature stats columns, the damage formula and turn order.
- No game material in git: no images, sounds, texts, data dumps. Only SPEC/notes, Python scripts, numeric tables with addresses,
  hashes. Large or game-derived files stay in the scratchpad (and copy them to `~/Documents/Claude_Workspace/REA-scratchpad-backup`
  before the session ends: /private/tmp is wiped on reboot).
- Do not write Swift for this slice.
- When a rule cannot be decoded, mark it [?] and list it at the end of SPEC.md with a proposed [I] rule; do not block on it.
- Commit and push the step4 folder when done (or at a clean checkpoint), message "Research: step 4 combat discovery (9-D)".
- Final report: what is decoded, what is [I]/[?], the list of "core" creature abilities kept for step 4.
