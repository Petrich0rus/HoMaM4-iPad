# Towns: t_town (class 95) and t_random_town (class 72) map-object payloads   (heroes4.exe GOG 1.3)
Legend: [D] decoded from exe disassembly; [I] inferred from data only; [V] validated by probe.py over all 105 maps.
Integers LE. str16 = u16 len + bytes (FUN_00879420). i16 = signed u16. Reader code: ext_towns.py (READERS {95,72}).
Validation: probe 95: ok=408 badnext=1 exc=0; probe 72: ok=247 badnext=1 exc=0 (both badnext = last object before terrain).
baseline5a with all ext_* files: 97/97 section-parsable maps walk to 'complete' (was: 36 town + 25 random_town stops).

## 1. town (95) reader 0x89a710 (t_town vtable 0x995f4c +0x90) [D][V]
```
u16 v              0..4 accepted; v<4 calls FUN_00417990(v) which rejects v<6  => only v==4 loads. Shipped: 4.
bset188 x2         FUN_00865be0 into a 0x40 temp (two 0x18 bitsets at +0,+0x18): u8 bver;
                   bver 0: 23 bytes (184 bits remapped via table 0xa8326c); bver 1: 24 bytes (remap table 0xa8382c);
                   bver >=2: FUN_00865f20, 24 bytes (188 bits). Shipped: bver 2 (presumably buildings present / allowed).
abstract_town_ver  FUN_00417900 (see 3)
```
After read (no stream data): builds defaults, FUN_0089a550, income table, etc.

## 2. random_town (72) reader 0x7f52b0 [D][V]
```
u16 v              0..7; v==7 shipped.
if v==7:
   FUN_0075cae0 (this+0x120):  u16 ver==0 ; str16 type in {"none","player","town"} (table 0x98ad44, FUN_0075c7c0)
        "none": nothing ; "player": u8 player ; "town": str16 (only accepted if byte this+0x120 != 0)   [D]
   abstract_town_ver (FUN_00417900)
else: FUN_00417990(v) directly (so only v==6 would load; unseen)
```

## 3. abstract town  FUN_00417900 / FUN_00417990 (shared t_abstract_town base) [D][V]
```
FUN_00417900: u16 v2 (6..8, else fail; shipped 8) then FUN_00417990(v2)
FUN_00417990(v) (v must be 6..8):
  u8 owner < 7  (6 = neutral)                 -> +0x4c
  FUN_00417f70 (v>=2): str16 name             -> +0xd4 (custom name flag +0xe4 = len!=0)
  (v>=2) u8 hasGarrison; if !=0: army FUN_00640d00 (section 4) -> +0x54
  FUN_00417c10 (v>=3): u8 custom; if custom: 6 bytes (43-bit set, FUN_00418a50 bits 0..0x2a) -> +0xa4
                       + 6 bytes (43-bit set) -> +0xcc;   else: u8 bool (sets/clears bit 3 of +0xa4)
  FUN_00417e40: 4 x FUN_007d2fd0 (built-in triggers, objects 0x40 bytes vtable 0x970aa4, -> +0xac..)
  FUN_00418080: u16 n ; n x FUN_007d3290 (timed events)
  FUN_004182f0: u16 n ; n x FUN_007d3530 (triggerable events)
  FUN_00418550: u16 n ; n x FUN_007d37f0 (continuous events)
  v>=7: u8 f; if f: 2 x FUN_00857ec0 (u8 ver==0 + 5 bytes = 36-bit set)
  v>=8: u8 -> +0xa0
```
Event element layouts [D] (same as scenario-level lists, sections/SPEC.md):
- 7d2fd0: u16 ver==0 ; Y ; u8 playerMask (7 bits, FUN_0048bfc0) ; u8 flags (2 bits, FUN_00727240; bit0->+0x3c bit1->+0x3d)
- 7d3290: u16 0 ; X = FUN_0088c700 (Y ; str16 ; u16 ; u16) ; u8 mask7 ; u8 mask2
- 7d3530: u16 0 ; FUN_008c8db0 (Y ; str16) ; u8 mask7 ; u8 mask2
- 7d37f0: u16 0 ; FUN_0063bda0 (Z ; str16) ; u8 bool ; u8 mask7 ; u8 mask2
- Y = FUN_00705e20: Z ; str16 ; 7 x u32 ;  Z = FUN_00827ef0: u16 scriptVersion (2) ; statement node.
The repeated `02 00 03 00 "seq" 00 00 ...` blocks in the data are the Z of these events (empty seq).

## 4. Army FUN_00640d00 (also used by garrison/mine, combat script node) [D][V]
```
u16 ver == 0 ; 7 x slot FUN_00640b50:
  i8 kind: -1 empty (obj 0x650f40, vt 0x9849a4, read 0x428da0 = nothing) | 0 creature stack | 1 hero | else fail
creature stack (ctor 0x63cf80, vt 0x98469c, read +0xd4 = FUN_0063e0f0):
  u16 sv (0..1) ; i16 creature (-1 or 0..0x49) ; i16 count (0 = default, computed from creature growth) ;
  sv>=1: FUN_00653760: u16 n ; n x artifact FUN_00664640
artifact FUN_00664640: i16 id (<=0xf8) ; if id in (0xa6, 0x7c) [spell scroll/parchment]: u16 spell (<=0xbc)
   (the decoded branch structure also calls 663640/663d10/664190; only the id/spell reads were confirmed)
hero (ctor 0x728470, vt 0x989310, read +0xd4 = FUN_0072f4e0):
  u16 hv (8..10, shipped 10) ; i16 heroType (-1..FUN_0073bb20()) ; u8 -> FUN_00729750 (+0x638, -1 or <0x30) ;
  i8 +0x634 in {-1,0,1} ; (hv>=5) i8 +0x6a0 ; (hv>=10) u8,u8 else u16,u16 ; u8 ; u8   (4 stat adjustments)
  str16 name (+0x5b4) ; str16 biography (+0x6a8)
  (hv>=3) u8 customSkills; if: 36 x i8 (-1 or 0..4)
  (hv>=4) bset188 (FUN_00865be0, spells -> +0x780)
  FUN_0072f940 (hv>=2): 14 x { u8 present; if: artifact }       (equipment)
  (hv>=1) FUN_00653760 (u16 n ; n x artifact)                  (backpack)
  FUN_00738700: 3 x 7d2fd0 ; FUN_00738830/738850/738870: counted 7d3290 / 7d3530 / 7d37f0 lists
  (hv>=9) u8 -> +0xa4
```
(armies topic owns this; decoded here because town garrisons contain heroes: 88 records.)

## 5. Script node grammar (needed inside town events) [D for statements' read sequences, I for some details]
Node = str16 name + payload. Statement factory table DAT_00a8d8c8 (54, registered by FUN_004111f0, names FUN_0081c390,
lookup FUN_0081c660), read = node vtable+0x10, args (stream, scriptVersion). Numeric expressions: DAT_00ad4260 (21,
FUN_00411290, names FUN_00828000, lookup FUN_00828dd0, reader FUN_00411300.. via +0x20 slot of the true vtable);
boolean expressions: DAT_00ad4200 (24, FUN_00411330, names FUN_008286b0, lookup FUN_00828e80).
Full table = STMT/NUM/BOOL dicts in ext_towns.py. Corrections vs sections/SPEC.md:
- text = str16 + (scriptVer>=1) seq (u16 n + n stmts)  [was 'SH': equal only when n=0]  (reader 0x826990 -> 0x833be0)
- combat = u8 kind (<3) + army FUN_00640d00 + stmt win + stmt lose   (0x824140 -> 0x822e90) [was H 0, B, slots]
- new: build u8(<0x2b), change_owner u8(<7), creatures u8+u16, rand u32+u32, not N, inc_exp u8+u32, ask S N N,
  dec/inc_{damage,max_hp,max_mana,speed} B H B, dec/inc_{luck,morale} B B, dec/inc_{mana,pop} B H, inc_move B B,
  give/inc_skill B B B, give_spell B H, take_material = give_material (u8 player<9 for ver>=2 ; 7 x u32), etc.
- give_material/take_material/win/lose/set_*_msg have scriptVersion gates (ver<2 alternate u8 range); shipped ver = 2.
These also fix the 6 SECTIONS-FAIL maps whose scenario scripts use rand/ask/month/inc_exp/false/creatures
(Black Jack, Final Grounds, Internal Conflict, Shadowsinforest, The Middle, Who First) -- not re-run here.

## 6. Open / not decoded
- Exact meaning of the two 43-bit sets in 417c10 and the two bset188 in the town reader (likely buildings allowed/present).
- Expression-vtable slot (+0x24 relative to the vtable my heuristic found) is inferred from consistency with data.
- FUN_00664640 sub-branches for non-spell artifacts (no extra reads seen in data).
- town v<4 / random_town v<7 paths unseen.
