# Army / creature stack / hero / monster readers (heroes4.exe GOG 1.3)
Decoded from disassembly (text.asm, asm.py); validated with probe.py / probe_army.py over the 105 shipped maps.
Notation: s8/s16 = signed. All reads go through stream vtable+0x18; u8 = FUN_004f0ec0, u16 = FUN_0057fd40, str16 = FUN_00879420.
Script-object records rec_2fd0 (FUN_007d2fd0), rec_3290 (7d3290), rec_3530 (7d3530), rec_37f0 (7d37f0) and the script node
grammar are owned by the ownables/scripts topics (dev_ownables.py); ext_army.py imports them from ext_ownables.py (else dev_ownables.py).

## script_block  (FUN_00525f70 = 525fe0 + 527240 + 5274a0 + 527700; same shape as hero 738700/738830/738850/738870)
  3 x rec_2fd0                                  (525fe0 / 738700; objects 0x40 bytes vt 0x970aa4)
  u16 n; n x rec_3290                           (527240 / 738830->738890)
  u16 n; n x rec_3530                           (5274a0 / 738850->738af0)
  u16 n; n x rec_37f0                           (527700 / 738870->738d50)
## artifact (FUN_00664640)   u16 id (<= 0xf8); if id in {0x7c, 0xa6} (scroll/parchment): u16 spell (<= 0xbc)
## artifact_list (FUN_00653760)   u16 n; n x artifact
## spell_bitset (FUN_00865be0 -> 865990)   u8 ver; ver==0: 23 bytes; ver==1: 24 bytes (865ab8); ver>=2: 24 bytes (865f20)

## army_stacks — shared 7-slot creature array (FUN_00640d00)  [V]
  u16 ver == 0                                  (anything else => fail)
  7 x slot (FUN_00640b50):
     s8 kind:  -1 -> empty stack (0x7c bytes, ctor 650f40, vt 0x9849a4; vt+0xd4 = 428da0 reads nothing)
                0 -> creature stack (0xb0, ctor 63cf80, vt 0x98469c; reader vt+0xd4 = FUN_0063e0f0)
                1 -> hero (0x7f8, ctor 728470, vt 0x989310; reader vt+0xd4 = FUN_0072f4e0)
                other -> fail
  then this->vt[0x34]() (recompute, no read).
  FUN_00640e90 (old variant, used by t_army ver<3 with flag): u16 0 + ONE slot, the 6 others empty.
### creature stack (FUN_0063e0f0)  [V]
  u16 ver (0..1); s16 creature (-1 or 0..0x49); s16 count (0 => default count derived from creature, FUN_006555a0/7f4570)
  ver>=1: artifact_list (carried artifacts)
### hero (FUN_0072f4e0)  [V on 465 army heroes + 46 prisons]
  u16 ver (8..10)
  s16 portrait/bio id (-1 .. < FUN_0073bb20())           -> +0x6d4
  s8  class -> FUN_00729750 (+0x638 must be -1 or < 48)
  s8  gender (-1,0,1)                                      -> +0x634
  [ver>=5] s8 -> +0x6a0
  [ver>=5] ver>=10: u8,u8 else u16,u16 ; then u8,u8      (4 primary-stat bonuses added to +0x18,+0x20,+0x28,+0x2c)
  str16 biography (+0x5b4) ; str16 name (+0x6a8)          (data: bio first, then name)
  [ver>=3] u8 hasSkills; if !=0: 36 x s8 skill level (-1 or 0..4)
  [ver>=4] spell_bitset (else default)
  [ver>=2] FUN_0072f940: 14 equipment slots x (u8 present; if present: artifact)
  [ver>=1] artifact_list (backpack)
  script_block (738700, 738830, 738850, 738870)
  [ver>=9] u8 -> +0xa4

## 'army' — anonymous army record, object list flag != 0 (t_army FUN_0051fa90, vt+0x90 = FUN_00523a30)  [V]
  u16 ver (0..9); ver==0 -> nothing else
  [ver>=2] u8 owner (<7) else 6                           -> +0x128
  ver>=3: army_stacks (640d00) ; ver<3: u8 b; b ? 640e90 : 640d00
  [ver>=4] (ver>=5: u8 f, else f=1); if f: u8 (s8+1 -> 642100), u8 (-> 6420f0)     (ai/behaviour flags)
  [ver>=6] script_block (525fe0, 527240, 5274a0, 527700)
  [ver>=7] s8 (-1 .. 5)                                   -> +0xbc
  [ver>=8] u8                                             -> +0xb4
  [ver>=9] u8 bool                                        -> +0xb0
  Shipped maps: always ver 9, flag byte 1 (both v27 and v29 scenarios).

## random_monster (64) / random_random_monster (66): FUN_007f3710  [V]
  u16 ver (0..4)
  [ver>=3] u8 f; if f: s8 (+1 -> +0xac), s8 (-> +0xb0)    else +0xac = 1 (+0xb0 = 3 when +0xac == 1)
  [ver>=2] script_block (525f70)
  [ver>=1] placement spec FUN_0075cae0: u16 0; str16 kind; kind 'player': u8; 'town': str16; else nothing
  [ver>=4] i32 min (>=0); i32 max (>= min); (min>0) == (max>0)       (+0xa8/+0xa4, stack size range)
## carryover_hero (13): FUN_005bf4a0  [D only — 0 records in shipped maps]
  u16 ver (0..2); [ver>=1] u8 owner (<7), str16 ; [ver>=2] u8 f; if f: s8 (+1 -> +0x80), s8 (-> +0x7c); script_block
## prison (56): FUN_00467f20  [V]
  u16 ver (0..1); ver==1: hero (this+0x48 ->vt[0xd4] = FUN_0072f4e0)
Version gates on scenario version 27/29: none of these readers look at the scenario version.
