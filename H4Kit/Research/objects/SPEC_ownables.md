# Ownables readers (heroes4.exe GOG 1.3) — ext_ownables.py
[D]=decoded from exe disassembly, [V]=validated with probe.py over 105 maps, [I]=inferred.
All payloads start right after the triple. `ver` below = object sub-version (u16 read by the reader), not scenario version
(no reader in this topic depends on scenario version 27/29).

## Shared pieces
- Script expression grammar (Z/Y/X, node payloads): copied from sections/SPEC.md (inferred from data, scripts topic).
  Z = FUN_00827ef0 -> 00410930: u16 scriptVer; node.  Y = FUN_00705e20: Z; str16; 7 x u32.  X = FUN_0088c700: Y; str16; u16; u16.
  FUN_0063bda0 = Z; str16.   FUN_008c8db0 = Y; str16.   [D]
- rec_2fd0 = FUN_007d2fd0: u16 v (==0); Y; u8 playerMask(7 bits ->+0x38); u8 flags(2 bits ->+0x3c,+0x3d)   [D,V]
- rec_37f0 = FUN_007d37f0 (obj 0x28, vt 0x971198): u16 0; Z; str16; u8 (->+0x24); u8 mask7; u8 mask2   [D]
- rec_3290 = FUN_007d3290 (obj 0x4c, vt 0x9711a0): u16 0; X; u8 mask7; u8 mask2   [D]
- rec_3530 = FUN_007d3530 (obj 0x50, vt 0x971190, "script object"): u16 0; Y; str16; u8 mask7; u8 mask2   [D,V n>0 seen 29x]
- army = FUN_00640d00 -> ext_army.army_stacks (army topic; u16 0 + 7 slots FUN_00640b50, kind i8 -1/0/1).
- spell_bitset FUN_00865be0: u8 v; 23 bytes if v==0 else 24.  placement_spec FUN_0075cae0: u16 0; str16 kind; 'player': u8, 'town': str16.  [D partially; V]

## owned base FUN_007d7270(stream, ownVer)   [D,V]
if ownVer>=1: u8 owner (<7, else fail) -> +0x4c   (else 6 = neutral)
if ownVer>=2: FUN_007d7590: u16 n; n x rec_3530
## lighthouse 38 / shipyard 81 / windmill 103 — reader 0x478a10;  creature_dwelling 21 — 0x43c9c0;
## weekly_material_generator 102 / random_weekly_material_generator 73 — 0x8ccd70   [D,V]
u16 ver (0..2); owned(ver).  (0x43c9c0 afterwards only fixes up its creature army in memory; no further reads.)
## random_creature_dwelling 61 — 0x43f450   [D,V]
u16 ver (0..3); owned(ownVer = 0 if ver==0, 1 if ver in 1..2, 2 if ver==3); if ver>=2: placement_spec (else default 0x75cd50)
## conservatory 18 — 0x437560   [D,V]
u16 ver (0..1); if ver==1: spell_bitset; spell_bitset
## random_conservatory 62 — 0x437ea0   [D; 0 instances in shipped maps]
u16 ver (0..2); if ver==2: spell_bitset x2; if ver>=1: placement_spec else default (0x75cd50)
## mine 44 / garrison 32 — 0x7d3f60 -> 0x7d3fb0(stream, ver)   [D,V]
u16 ver (<=2)
if ver>=1: u8 owner (<7) else owner=6                    -> +0x4c
if ver>=2 and owner!=6: u8 bool                          -> +0xdc (default 1)
if ver>=2: 4 x rec_2fd0 (objects +0x9c..+0xa8)
FUN_007d4150: if ver>=2: u16 n; n x rec_37f0
FUN_007d4390: if ver>=2: u16 n; n x rec_3290
FUN_007d45c0: if ver>=2: u16 n; n x rec_3530
if ver>=2: u8 hasArmy; if !=0: army (FUN_00640d00 -> +0x54) else army cleared (0x63f830)
## abandoned_mine 0 — 0x4263e0   [D,V]
u16 ver (<=1); if ver>=1: 4 x rec_2fd0; lists 0x426510 (rec_37f0), 0x426750 (rec_3290), 0x426970 (rec_3530), each u16 n when ver>=1;
u8 hasArmy; if !=0 army 0x640d00 else default 0x425340.  (no owner byte)
