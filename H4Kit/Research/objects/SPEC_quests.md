# Quests + misc object readers (heroes4.exe GOG 1.3) — ext_quests.py
Status: [D] decoded from disassembly (text.asm), [I] inferred from data. All validated with probe.py over 105 maps.
str16 = FUN_00879420. "script" = FUN_00410930: u16 version (2 in maps) + action node. "expr" = FUN_004112a0 (->411990/411800):
u16 version + bool-expression node. Node = str16 class name + payload (grammar: sections/SPEC.md, extended below).

## Quest core FUN_007ed980(stream, progress, has) [D]
if has: str16 (+0x84), str16 (+0x70), str16 (+0x60), str16 (+0x50)  ; script -> +0x48 ; expr -> +0x4c
## quest_gate 57, reader 0x7eec70 [D]   u16 v (0..1); core(has = v>=1).                       probe: ok 70/70
## quest_guard 58, reader 0x7ef7e0 [D]  u16 v (0..2); if v>=1: core(1), str16 (+0x98); if v>=2: FUN_007ef410 = script (+0xa8).  ok 17/17
## seers_hut 77, reader 0x7efac0 [D]    u16 v (0..2); if v>=1: core(1), str16 (+0x98), [v>=2: script(7ef410)], str16 (+0xac), [v==1: script(7ef410)].  ok 87/87
## school 76 (all 8 subclasses) [D]  readers 0x766cd0 (magic_university, war_college), 0x81a1c0 (school_of_magic, school_of_war),
   0x8cb860 (library, war_institute), 0x58c080 (witchs_hut, beastmasters_hut) — identical layout:
   u16 v (0..1); if v==1: 2 x FUN_00857ec0 (u8 must be 0 + 5 bytes 36-bit skill set). v==0: defaults from vtable +0xb4/+0xc0.
   ok: 90/112/112/107/131/153/122/94, 0 fail.  Keys (76,'magic_university') ... (76,'beastmasters_hut').
## shrine 82, reader 0x46c4a0 [D]   u16 v (0..2); v==2: FUN_00865be0 = u8 sub + FUN_00865990(sub); v==1: FUN_00865990(0); v==0: all spells.
   FUN_00865990(sub): sub==0 -> 0x17 bytes (184-bit spell set), sub>=1 -> 0x18 bytes (192 bits; 0xba..0xbc spells). ok 385
## random_shrine 67, reader 0x46cfd0 [D]  u16 v (0..3); spell set as shrine (v>=2 / v==1); if v>=3: selector (FUN_0075cae0), else default (75cd50).  ok 292
## random_teacher 69, reader 0x42e4b0 [D]  u16 v (0..1); if v>=1: u16 9-bit mask (allowed teacher kinds), selector; v==0: mask=0x1ff.  ok 205
## random_temple 70, reader 0x473aa0 [D]   u16 v (0..1); if v>=1: selector.  ok 66
## selector FUN_0075cae0 [D/I]  u16 0 ; str16 kind (FUN_0075c7c0: 'none'=0, 'player'=1, 'town'=2) ; kind1: u8 ; kind2: str16 (town name,
   read only if the object's flag byte is set; always set in maps [I]) ; kind0: nothing.
## spell_artifact (artifact subclasses 124/166 = parchment/scroll), reader 0x430e10 [D]  u16 v (0..1); if v: u32 spell id
   (+ checks triple class 0xa6 for spell lookup). ok 9 parchment, 0 scroll in maps.

## Script grammar additions (needed by quest scripts; class tables from sections/classes.txt)
[D] from the node readers: text = S + L (FUN_00826990: str16, then if scriptVer>=1 FUN_00833be0 = u16 n + n child nodes; replaces 'SH');
inc_damage/dec_damage/inc_max_hp/dec_max_hp/inc_max_mana/dec_max_mana/inc_speed/dec_speed = B H B (0x81dac0);
inc_mana/dec_mana = B H (0x81d7b0); inc_pop/dec_pop = B H (0x81f720); inc_exp = B I (0x82eae0); give_spell = B H (0x82bda0);
inc_move = B B (0x82d330); inc_luck/dec_luck/inc_morale/dec_morale = B B (0x81ed00); give_skill, inc_skill = B B B (0x82af60/0x82b230);
build = B, change_owner = B (0x8239e0/0x823bd0).
[I] (data only; some exe readers seem to disagree, e.g. 0x81f270 reads u32 — scripts agent should confirm):
not = N; is_computer, total_creatures, total_heroes, exp_level, player = B; materials = B B; mastery = B B; creatures = B H;
take_material = B + 7xu32 (like give_material); take_creature = B H H; rem_artifact = B, u16 n, n x u16; false, dow, week, month, wom = ''.
Unseen node classes are unspecified (ask, rand, neg, has_alignment, is_alignment, ...).
