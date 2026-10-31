t_army reader 0x523a30: u16 v(0..9); v==0 -> done. v>=2: u8 owner<7 (else 6). v>=3: 640d00 ; v<3: u8 b ? 640e90 : 640d00.
v>=5: u8 f; f==0 -> skip next two. v>=4 (and f!=0): u8 s8, u8 x. v>=6: 525fe0(stream,0), 527240,5274a0,527700(stream,0,&vec).
v>=7: s8 (-1..5). v>=8: u8. v>=9: u8 bool.
640d00: u16 v==0; 7 x 640b50(stream) slot (null->fail). 640e90 (army v<3 alt): u16 0; 1 x 640b50, 6 slots default
640b50 slot: s8 kind: -1 empty(0x7c, ctor 650f40) 0 creature(0xb0,63cf80) 1 hero(0x7f8,728470) else fail; then obj->vt[0xd4](stream)
empty stack vt 0x9849a4 reader 428da0: nothing. creature stack vt 0x98469c reader 63e0f0: u16 v<=1; s16 type (-1 or 0..73); s16 count (0=>auto); v>=1: 653760(stream)
653760 (stack v>=1 extra): u16 n; n x 664640(stream, elem 0x5c bytes)
664640 artifact: u16 id<=248; if id in (124,166): u16 spell<=188
data: army v9 owner 6 creature: 01 09 00 06 | 00 00 | 00 01 00 1f 00 00 00 00 00 | ff x6 | 00(f) | 02 00 03 00 'seq'...  hero armies: slot kind 1, hero v=0x0a
525fe0: 3 x 7d2fd0(stream) (script/event objects, 0x40 bytes vt 0x970aa4)
army v>=6: 525fe0 (3x rec_2fd0), 527240 (u16 n x rec_3290), 5274a0 (n x rec_3530), 527700 (n x rec_37f0)  [rec_* decoded by ownables agent in dev_ownables.py]
hero vt 0x989310 reader 72f4e0: u16 v 8..10; s16 (57fd40) >= -1 < 73bb20(); s8 -> 729750 (field 0x638 -1 or <48); s8 0x634 in -1,0,1;
 v>=5: s8 0x6a0; v>=5: (v>=10: u8,u8 else u16,u16), u8, u8 (added to stats 0x18,0x20,0x28,0x2c);
 str16, str16; v>=3: u8 has; if has: 36 x s8 (-1 or 0..4); v>=4: 865be0 else default; 72f940(stream,v); v>=1: 653760 artifacts;
 738700, 738830, 738850, 738870; v>=9: u8
72f940(stream,v): v>=2: 14 x (u8 has; has: artifact 664640). 738700=3x rec_2fd0; 738830->738890 list rec_3290; 738850->738af0 list rec_3530; 738870->738d50 list rec_37f0
VALIDATED army_record: 2785 ok, badnext 16 all at terrain, 139 exc all script-grammar gaps (scripts topic) + 1 hero in MoMM (script)
random_monster 7f3710: u16 v<=4; v>=3: u8 f; f: s8,s8; v>=2: 525f70(stream,0); v>=1: 75cae0; v>=4: i32 a>=0, i32 b>=a, (a>0)==(b>0)
525f70 = 525fe0+527240+5274a0+527700 (script block). 75cae0: u16 0; str16 kind; 'player'(1): u8; 'town'(2): str16; other: nothing (= ownables spec_75cae0)
carryover 5bf4a0: u16 v<=2; v>=1: u8 owner<7, str16; v>=2: u8 f; f: s8,s8; 738700..738870 block. prison 467f20: u16 v<=1; v==1: hero(+0x48)->vt[0xd4]
