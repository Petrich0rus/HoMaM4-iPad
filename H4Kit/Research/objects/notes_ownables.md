# ownables notes (WIP)
7d3f60: u16 ver -> 7d3fb0(stream, ver)
7d3fb0: ver<=2; ver>=1: u8 owner<7 (else 6) ->+0x4c; ver>=2 && owner!=6: u8 bool ->+0xdc (else 1)
  ver>=2: 4x 7d2fd0 on objs +0x9c..+0xa8
  7d4150(stream,ver): ver>=2: u16 n; n x obj0x28 (vt 0x971198) read 7d37f0
  7d4390: ver>=2: u16 n; n x obj0x4c (vt 0x9711a0) read 7d3290
  7d45c0: ver>=2: u16 n; n x obj0x50 (vt 0x971190) read 7d3530
  ver>=2: u8 ... (tail TBD)
7d2fd0: u16 v==0; 705e20(stream,0); u8 player mask(7 bits)->+0x38; u8 (2 bits)->+0x3c,+0x3d
  tail: ver>=2: u8 hasArmy; if !=0: army 640d00 (at +0x54) else clear (63f830)
705e20(stream,0): 827ef0(stream,0); str16 ->+0x28; 7 x u32 ->+0xc..
7d37f0 (obj 0x28): u16 0; 63bda0(stream); u8 ->+0x24; u8 mask7; u8 mask2
7d3290 (obj 0x4c): u16 0; X=88c700; u8 mask7; u8 mask2   (== sections elemA)
7d3530 (obj 0x50): u16 0; 8c8db0; u8 mask7; u8 mask2
script node grammar: copied from sections/parse_sections.py
STATUS: dev_ownables.py mine/garrison pass except army (640d00) cases: 44 ok2322 exc35; 32 ok34 exc95
