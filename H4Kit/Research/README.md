# Research notes (reverse engineering of heroes4.exe)

Specs and Python reference implementations produced while decoding the map format (slice 5).
They contain no game data: no exe, no disassembly, no resources. The scripts expect, next to them, a
directory `advobj/adv_object/` extracted from the player's own data (`h4tool extract <Data> advobj adv_object.`)
and the game mounted at the path written in the scripts.

- `PLAN-objects.md`: plan for slice 5 (waves 5a–5d).
- `sections/`: sections before the objects and the script grammar (`SPEC*.md`, `scripts.py`, `parse_sections2.py`).
- `objects/`: object list, class table (`SPEC.md`), one spec per family (`SPEC_*.md`) and its reader (`ext_*.py`),
  harness `chain.py` (+ `probe.py`: validates one class on its own).
- `baseline5b.py` → `baseline5b.txt`: reference over the 105 maps; `h4tool objects` must produce it byte for byte.
