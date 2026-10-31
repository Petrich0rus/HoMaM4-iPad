# Common brief for object-reader discovery agents (HoMM4 map objects)

You are one of several parallel read-only reverse-engineering agents. Do NOT edit anything under
/Users/petrichorus/Documents/Claude_Workspace/REA/H4Kit. Do not spawn subagents. Do not run detached processes.
SCRATCH = /private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad

Inputs
- SCRATCH/objects/SPEC.md: object list framing, class enum, class table with reader addresses (vtable+0x90), known readers.
- SCRATCH/sections/SPEC.md: body sections + script-expression grammar (inferred).
- heroes4.exe: disassembly SCRATCH/objects/text.asm (objdump, Intel syntax), PE copy SCRATCH/objects/heroes4.exe,
  helper scripts SCRATCH/objects/pe.py, asm.py, asm2.py, trace.py (read them). The REA MCP (Ghidra) has heroes4.exe open:
  load tools with ToolSearch "select:mcp__rea__procedure_pseudo_code,mcp__rea__batch_decompile,mcp__rea__procedure_callees,mcp__rea__xrefs";
  never call open_binary/close_binary. REA output is ~2x duplicated and large: decompile one or a few functions at a time,
  prefer the disassembly for vtable-only functions (Ghidra may not have them as functions). Stream reads are
  vtable call +0x18(buf, len) on the stream object; strings = FUN_00879420 (u16 len + bytes).
- Real data: maps/**/*.h4c (105) under "/Volumes/Heroes of might and magic IV/Heroes IV.app/Contents/SharedSupport/prefix/drive_c/GOG Games/HoMM 4 Complete/maps/".
  Body = gzip.decompress(file[15:]). Scenario version 27 or 29 = u16 at offset 0 of the decompressed data.
- Python harness in SCRATCH/objects: chain.py (R reader class with u8/u16/u32/str16, walk), probe.py (validate ONE class
  reader over all maps: finds every record of the class, runs your reader, checks the next record starts right after).
  Coordinates are signed i32 (x, y may be -1). Usage: `cd SCRATCH/objects && python3 -I probe.py <cid> [subname] <file.py> <func>`.
  The ~28 "next?" failures per class that show non-record bytes right after are usually the last object before the terrain;
  judge by looking at the bytes. Run python with -I.

Deliverables (your TOPIC is given in your prompt)
1. SCRATCH/objects/ext_<topic>.py defining READERS = {key: fn(r, ver)} where key = class id int, or (class id, subclass name
   lowercase) for subclass-specific readers, or 'army' (anonymous army record, flag != 0), or 'spell_artifact'.
   Each fn consumes exactly the class payload (after the triple), asserting the game's validity checks. Shared helpers
   (army/creature stack, hero, script list, resources...) go in clearly named functions in your file.
   Develop under another name (dev_<topic>.py) and only create ext_<topic>.py once its readers pass probe.py, because
   chain.py auto-loads every ext_*.py file (other agents' too).
2. SCRATCH/objects/SPEC_<topic>.md: byte layout of each reader, with exe addresses for every function involved, version
   gates for versions 27/29 (and object sub-versions), validity checks, and what is inferred vs decoded from the exe.
3. Validation: probe.py results per class (ok / badnext / exceptions) — target: 0 exceptions, badnext only at list ends.
   Then `cd SCRATCH && python3 -I baseline5a.py > SCRATCH/objects/run_<topic>.txt` and report how the stop reasons changed.
Final message (< 50 lines): per class status (decoded from exe / validated count), open issues, file paths.
Other topics being handled in parallel: towns, armies(army record + creature stacks + heroes + monsters), ownables
(mines/garrisons/dwellings/generators/conservatories), quests+misc, scripts (script node grammar). If you need a helper
owned by another topic (e.g. the army/creature-stack reader), decode it yourself only as far as you need it, and say so.
