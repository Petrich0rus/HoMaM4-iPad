# scripts agent progress notes
- 3 class tables: actions (54, names builder 81bb00, factory reg 4111f0 -> DAT_00a8d8c8, lookup 81c660, create 410b80, read = node vt+0x10)
  numeric exprs (21, names 828000, reg 411290 -> ad4260, lookup 828dd0, read vt+0x20), bool exprs (24, names 8286b0, reg 411330 -> ad4200, lookup 828e80, read vt+0x20)
- classes.txt = name, factory vt, create fn, node vt, reader fn (from reg.py tab)
- MAP read slots: action vt+0x10 (via 4109a0 from Z=410930: u16 ver then node), expr vt+0x24 (num read 411230->4114e0, bool read 4112d0->411800). (+0xc/+0x20 = alt format, 410a90/411260/411300)
- reader args (stream, scriptVer). readers_c.txt = condensed disasm of each reader (cdis.py)
- artifact elem (664640): H id<=248; if id in (0xa6,0x7c): H spell<=188
- army 640d00: H ver==0; 7x slot 640b50: B type (0xff empty, 0 creature stack 63cf80/vt+0xd4=63e0f0, 1 hero 728470)
- creature stack 63e0f0: H ver<=1, H creature(-1 or <74), H count; ver>=1: H n + n x artifact(664640) [653760]
- if 8248d0: bool(4112d0) + 822e90 = 2 actions(4109a0). combat 824140: B<3, army, 2 actions. seq 833be0: H n, n actions. text 826990: S; ver>=1 -> seq payload
- has_artifact 82c660: B flag; flag? B<9 (ver>=2) [ver<2: B<8, remap +1 if >0] : B<4; then artifact
- skill 82af60 (give_skill + bool idx3): B<10,B<36,B<5; inc_skill 82b230: B<10,B,B<36; inc_level 82bd00 B<10,B; give_spell 82bda0 B<10,H<188 (+864c30 check); mastery 82cc00 B<10,B<36
- all readers decoded (see SPEC_scripts.md once written). P = player sel: ver>=2 B<9 else B<8. hero sel B<10.
- header ver>=24 two flags -> 816970 each (victory, defeat cinematic): u16 ver==0, S text, S movie (816b70: matched vs 74 names via 8167f0, empty ok), S (816cd0: 72 names via 8168a0). NOT scripts.
