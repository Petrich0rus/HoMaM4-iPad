# HoMM4 scenario body: from end of header to the object count (FUN_004ced20's first u32)

All integers little-endian. `S` = string = u16 length + raw bytes (FUN_00879420, no terminator, Windows-1252).
`ver` = scenario version (27 or 29 in shipped maps); `pc` = player count from header (header+0x34).
Stream read vtable slot +0x18 = read(buf,len). Validated by /private/tmp/.../sections/parse_sections.py: 85/85 maps parse
to a plausible object count (412..11308, median 2426); body offsets are printed in out.txt.

## Sequence (loader FUN_004d12d0), versions 27/29
1. FUN_004cf440: no stream read.
2. FUN_004cfa90 "list A": u16 n; n x elemA (FUN_00726af0)
3. FUN_004cfcf0 "list B": u16 n; n x elemB (FUN_00726d70)
4. FUN_004cff50 "list C": u16 n; n x elemC (FUN_00726de0)
5. FUN_004d0200 "list D" (only if ver>=12): u16 n; n x elemD (FUN_00726f90)
   (A..D are the scenario event/script lists: A = timed/triggered events, D = continuous events, etc.; exact game meaning unconfirmed)
6. 12 x FUN_007c6340(i): (ver>=13) u16 version (must be 0, else load fails); u8 flag; u16 value (0xffff in all maps);
   if flag==0: nothing more (default list from table DAT_009858e4[i], FUN_007c6610);
   if flag!=0: u16 count; count x polyObj (FUN_007c7130): u16 ver(0); S typeName; payload by type
       "artifact": 6 bytes (u16 id, u16 1, u16 0) ; "material": 5 bytes (u8 resource, u32 amount)   [other types: not seen; class table of 0x36 names unresolved]
   Seen only in Demonary of Doom, Head of the Dragon, Hell hath no fury (entry 0 or 4).
7. FUN_004d0530 (ver>=16): pc x { u8 colour; u8 flag; [flag: u16]; (ver>=23) u8 }   -- colour must match a player (else load fails)
8. FUN_004d0750 (ver>=18): u8 flag; if flag: bitset248 (FUN_00551650 -> FUN_00551980): u16 0, u16 nbits (<=248, shipped=232), ceil(nbits/8) bytes
9. FUN_004d0920 (ver>=18): u8 flag; if flag: u16 len + len raw bytes (FUN_0059f110)
10. FUN_004f0ec0 (ver>=18): u8 flag; if flag!=0 then FUN_00857ec0: u8 (must be 0) + 5 bytes (36-bit set). Shipped maps: flag 0.
11. FUN_004d0c10 (ver>=18): u8 flag; if flag: u16 nbits (<=188), ceil(nbits/8) bytes (NO leading u16 0 here)
12. FUN_004d1080: reads NOTHING for ver>=24 (ver 21..23: two u8 flags each optionally followed by FUN_00816970 data).
13. (ver>=22) 2 x FUN_005515c0: bitset248 as in 8 (u16 0, u16 nbits<=248, bytes)
14. (ver>=23) FUN_005480b0, FUN_0085e790, FUN_0085e790: u16 version (0), u16 n, n x { u16 id (<248 for first, <188 for others); u8 val in {1,2} }
15. -> FUN_004ced20 object list starts: u32 object count.

Observed fixed prefix for all maps without scripts: `00 00 | 00 00 | 00 00 | 00 00 | 12x(00 00 00 ff ff) | pc x (colour 00 00) | 01 [00 00 E8 00 + 29 bytes] | 00 | 00 | 00 | [00 00 E8 00 + 29 bytes] ...`

## Element layouts
- elemA (FUN_00726af0): u16 ver (0); X; u8 mask6 (players); u8 mask2 (flags)
- elemB (FUN_00726d70): u16 ver (0); Y; S
- elemC (FUN_00726de0): u16 ver (0); Z; S
- elemD (FUN_00726f90): u16 ver (0 or 1, else fail); Y; if ver==1: u8 mask6, u8 mask2; S
- X (FUN_0088c700) = Y ; S ; u16 ; u16
- Y (FUN_00705e20) = Z ; S ; 7 x u32      (the 7 u32 = resources gold,wood,ore,mercury,sulfur,crystal,gems style)
- Z (FUN_00827ef0 -> FUN_00410930/004109a0) = u16 scriptVersion (2 in maps) ; Node
- Node (FUN_004109a0 -> FUN_00410b80 + vtable+0x10): S typeName (one of 0x36 registered names, lookup FUN_0081c660), then payload by class.
  Class payload readers are virtual; the table (DAT_00a8d8c8) was NOT decompiled. The payloads below are INFERRED FROM DATA (all 85 maps parse), not from decompilation.

## Script node payloads (inferred; types: B=u8 H=u16 I=u32 S=string N=child node)
seq: H n, n x N | if: N cond, N then, N else | and, or, binary operators with non-alpha names ("==", "+", ...): N N |
var: S | lit: I | day, true, rem_event, rem_this, no_op: (none) | is_eliminated: B | is_dead, is_imprisoned: S |
win, lose, enable_vc, disable_vc: B | set_num, set_bool: S N | text: S H | detonate: S |
owns_town, owns_hero, has_hero: B S | gosub: S | inc_level, dec_morale, is_color: B B | is_human: B |
give_material: B + 7xI | set_l_msg, set_v_msg, set_lc_text, set_vc_text: B S | has_artifact: B B H | give_creature: B H H |
give_artifact: B, H n, n x H | combat: H ver(0), B, 7 slots {B marker: 0xff = empty, 0 = filled followed by H(1), H creature, I count}, then N N (win, lose).
Names seen in the 85 maps and not covered => none (all parse). Unseen classes (of the 0x36=54) are unspecified.

## Validity checks the game makes (useful for validation)
elem version bytes != 0 (A,B,C), D ver>1, avail-list ver != 0, 12-list loop; bitset nbits > 248 (or >188 for the 0xbd ones); idmap id >= 248/188, val not in {1,2};
FUN_00857ec0 first byte != 0; 004d0530 player colour not found; unknown script class name (index outside 0..0x35 => null object => failure).
