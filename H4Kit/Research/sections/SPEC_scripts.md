# HoMM4 script grammar, decoded from heroes4.exe

This replaces the data-inferred node table in sections/SPEC.md. Implementation: sections/scripts.py.
Tools (in sections/): names.py (gets the name tables out of the builder functions), reg.py (`python3 reg.py tab` > classes.txt: name -> factory vtable -> create fn -> node vtable -> reader), cdis.py (condensed disassembly of a reader), readers_c.txt (every reader, condensed).

Notation: B = u8, H = u16, I = u32 (signed where it matters), S = str16 (FUN_00879420), A = action node, N = numeric expression, Q = boolean expression.
`v` = script version (the u16 in front of the root node, 2 in every shipped map). It is passed as the 2nd argument to every reader.

## Framing
- Z = FUN_00827ef0 -> FUN_00410930: H v, then A (FUN_004109a0). A null or failed node makes the load fail.
- A = FUN_004109a0 -> FUN_00410b80: S name; FUN_0081c660 looks the name up in a map built by FUN_0081c390 from the 54 names of FUN_0081bb00. An index outside 0..0x35 fails. The factory DAT_00a8d8c8[idx] (registered by FUN_004111f0) creates the node, and the game calls node vt+0x10 (stream, v).
- N = FUN_00411230 -> FUN_004114e0: S name, lookup FUN_00828dd0 (21 names, FUN_00828000), factory DAT_00ad4260 (reg FUN_00411290), read through node vt+0x24.
- Q = FUN_004112d0 -> FUN_00411800: S name, lookup FUN_00828e80 (24 names, FUN_008286b0), factory DAT_00ad4200 (reg FUN_00411330), read through node vt+0x24.
- Second read path, NOT used for map loading: FUN_00410a90 (action vt+0x0c), FUN_00411260 -> 00411340 and FUN_00411300 -> 00411670 (expr vt+0x20). Seq (FUN_00833dd0) uses it. The payloads are often the same, but some differ (for example is_human vt+0x20 = u32).
- So there are 99 classes in total: 54 actions + 21 numeric + 24 boolean. The "0x36 = 54" table covers only the actions.

## Shared sub-records
- P (player) = FUN_00830140 / FUN_004f0ec0 pattern: v>=2: B < 9; v<2: B < 8 (the game remaps the value).
- HS (hero selector) = B < 10.
- artifact = FUN_00664640: H id <= 248; if id is 0xa6 or 0x7c, then H spell <= 188.
- army = FUN_00640d00: H ver == 0; 7 x slot (FUN_00640b50): B type: 0xff = empty, 0 = creature stack, 1 = hero (FUN_00728470, not decoded, raises), anything else fails.
- creature stack = FUN_0063e0f0 (vt+0xd4 of the class built by ctor FUN_0063cf80): H ver <= 1; H creature (-1 or < 74); H count; if ver >= 1: H n + n x artifact (FUN_00653760).
- seq payload = FUN_00833be0: H n, n x A.

## Actions (index: name, reader, payload)
0 build 8239e0: B<43 | 1 change_owner 823bd0: B<7 | 2-5 clear_lc_text/clear_l_msg/clear_vc_text/clear_v_msg 830140: P
6 combat 824140: B<3, army, A (win), A (lose) | 7 if 8248d0: Q, A, A (FUN_00822e90 = two actions)
8 dec_mana / 26 inc_mana 81d7b0: HS, H
9,11,12,15 dec_damage/dec_max_hp/dec_max_mana/dec_speed and 27,31,32,36 inc_damage/inc_max_hp/inc_max_mana/inc_speed 81dac0: HS, H, B(flag)
10,13 dec_luck/dec_morale and 30,33 inc_luck/inc_morale 81ed00: B<4, B
14 dec_pop / 34 inc_pop 81f720: B<=8, H | 16 detonate / 52 gosub 826690: S | 17 disable_vc / 19 enable_vc 830140: P
18 text 826990: S; if v>=1: seq payload (H n, n x A)
20 give_artifact / 49 rem_artifact 821840: B<4, H n, n x artifact
21 give_creature / 50 take_creature 824ed0: B<3, H creature<74, H count
22 give_material 82fdf0 / 51 take_material 82fd20: P (FUN_004f0ec0), 7 x I
23 give_skill 82af60: HS, B skill<36, B level<5 | 24 give_spell 82bda0: HS, H spell<188 (plus check FUN_00864c30)
25 inc_move 82d330: B<3, B | 28 inc_exp 82eae0: HS, I | 29 inc_level 82bd00: HS, B | 35 inc_skill 82b230: HS, B, B skill<36
37 no_op, 40 rem_event, 41 rem_this 410c50: nothing | 38 lose / 53 win 830140: P
39 ask 832280: S, A (yes), A (no) | 42 seq 833be0: H n, n x A
43 set_bool 835cf0: S, Q | 46 set_num 835910: S, N
44,45,47,48 set_lc_text/set_l_msg/set_vc_text/set_v_msg 834760: P, S

## Numeric expressions (FUN_00828000 order)
0 creatures 825e50: B<3, H creature<74 | 1 day, 2 dow, 9 month, 19 week, 20 wom 7efef0: nothing
3 / 8 - 12 + 14 % 15 * 820410: N, N | 4 exp_level 82cf80: HS | 5 mastery 82cc00: HS, B<36 | 6 lit 830650: I
7 materials 831250: P, B<7 | 10 neg 81ff40: N | 11 player 830140: P | 13 rand 832780: I lo, I hi
16 total_creatures, 17 total_heroes 825b20: B<3 | 18 var 837540: S

## Boolean expressions (FUN_008286b0 order)
0 and, 14 or 82f570: Q, Q | 13 not 82f0a0: Q | 1 has_alignment 821080: B<3, B<6 | 2 has_hero 821280: B<3, S
3 "give_skill?" (the exe's literal name for has-skill) 82af60: HS, B<36, B<5 | 4 ==, 6 >, 7 >=, 11 <, 12 <= 832e90: N, N
5 false, 22 true 7efef0: nothing | 8 has_artifact 82c660: B flag; flag != 0: P, else B<4; then artifact
9 is_dead, 10 is_imprisoned 836470: S (must not be empty) | 15 is_alignment 830fd0: P, B<6 | 16 is_color 831250: P, B<7
17 is_computer, 18 is_eliminated, 19 is_human 830140: P | 20 owns_hero, 21 owns_town 834760: P, S | 23 var 837540: S

## Differences from the inferred grammar
These are byte-compatible on all shipped data.
- combat: the exe reads B<3 first, then the army (H ver=0, 7 slots). The inferred version read "H ver, B" (also 3 bytes).
- text: the inferred "S H" is S + seq payload with n = 0.
- give_artifact: the inferred "n x H" is n x artifact; the extra spell H appears only for ids 0xa6/0x7c.
- Binary operators: only + - * / % (numeric) and == > >= < <= (boolean) exist. There is no "!=".
- Classes that never appeared in the 85 main maps now parse (rand, ask, month, inc_exp, false, creatures, ...).

## Containers
- Y = FUN_00705e20: Z; S; 7 x u32. X = FUN_0088c700: Y; S; H; H. elemA..D: see SPEC.md.
- FUN_007d3530 (object-embedded event, 6 callers including 418446/426aff/5275f0/738c40/7d474f/7d76e6) = H ver==0; Y (FUN_008c8db0 = Y + S); B player mask (7 bits); B mask (2 bits). scripts.read_event_obj.

## Scenario header, version >= 24 (FUN_0077a420)
- Two blocks (victory, defeat), each: B flag; if flag: FUN_00816970 = H ver==0; S text; S movie (FUN_00816b70, matched against 74 names via FUN_008167f0, empty allowed); S (FUN_00816cd0, 72 names via FUN_008168a0).
- These are cinematic/text blocks, not scripts. Examples: Seven Steps To Glory has ("", "dead_black_dragon", "chaos_a_prologue") and ("", "dead_black_dragon", ""); The Four Horsemen has defeat-flag 0, then the victory text with "last_stand", "".
- The rest of the header after these blocks follows hdr.py: ver>=27 S, ver>=29 B. scripts.read_header_cine, hdr2.py.

## Not decoded
- Hero in a script army slot (type 1, FUN_00728470): raises ScriptError. Not seen in any map.
- The movie name lists (FUN_008167f0 / 008168a0): names are not validated.
- Version gates for v < 2 are implemented only for P. Maps use v = 2.

## Validation
`python3 -I parse_sections2.py` over maps/**/*.h4c gives 105/105 OK, object counts 412..15588 (median 2426).
On the 97 maps that parse_sections.py handles: body start and object-list offset are identical in all 97 (0 differences).
The 8 maps that are new successes: Black Jack, Final Grounds, Internal Conflict, Seven Steps To Glory, Shadowsinforest, The Four Horsemen, The Middle, Who First. In each, the object list starts with a well-formed record (count, x, y, z, name string).
