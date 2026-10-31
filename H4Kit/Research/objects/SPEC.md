# HoMM4 map object list (FUN_004ced20) - byte-level specification (heroes4.exe, GOG 1.3)

Status legend: [V] validated by chaining real records over all 105 shipped maps (python/chain.py);
[D] decoded from disassembly, not yet validated; [?] open.
All integers little-endian. "str16" = u16 length + that many bytes (FUN_00879420, no terminator, latin1).

## 1. Object list framing (FUN_004ced20(stream, scenarioVersion)) [V]
```
u32 count
repeat count times:
  u32 x ; u32 y ; u32 level          (confirmed from asm: first two reads go to the position key, third to level)
  u8  flag
  if flag == 0:                      -- "named" object
     str16 modelName                 -- adv_object resource name (e.g. "castle.Random Town"), FUN_00879420
     [FUN_007c7ca0(modelName) instantiates the class, see section 2]
     if version >= 14:  TRIPLE (FUN_00465e50)
         u16 0                       (must be 0, otherwise read fails)
         u16 id1 ; str16 name1       (class,       e.g. 71, "random_town")
         u16 id2 ; str16 name2       (subclass,    e.g. 0,  "left")
         u16 id3 ; str16 name3       (index,       e.g. 0,  "")
       The ids are resolved against the class/sub/index name tables; the result is compared
       (FUN_004cf190) with the triple of the created object (FUN_00875ca0). Mismatch => object list fails.
       (The ids written in the files are NOT the registry indices; resolve by NAME.)
     object->vtable[0x90](stream, progress)   -- the class reader, section 3. Failure => map load fails.
  else (flag != 0):                  -- anonymous army object (version >= 5; for version < 5 it reads a name instead)
     object = FUN_0051fa90(1) = t_army (0x180 bytes, vtable 0x97ac4c / secondary 0x97aba0 at +0xc)
     t_army::vtable[0x90] = 0x523a30 (reads the army, in practice a map monster stack)   [?] layout open
  then the object is inserted into the map at (x,y,level) (FUN_004e9fc0).
```
Version gating: version<5 reads name for every record; version 4 additionally reads a trailing u16.
Shipped maps are v27/v29 so only the paths above matter. Positions: 3rd u32 is level (0/1 in shipped maps).
Validation: first record found by scanning for a plausible record (find_start in chain.py); u32 count sits right before it.

## 2. Model name -> class (FUN_007c7ca0) [D, cross-checked with data]
FUN_007c7ca0(name): looks up the adv_object model (name -> t_adv_object_model, FUN_00412550) and reads its
classification triple (+0x48 class index, +0x4c subclass, +0x50 index). Then in the global table
`DAT_00ac08e0` (105 entries x 0x14 bytes, static init 0x7c7b80) it picks the factory:
  entry[class].subVec[subclass].idxVec[index] -> else entry[class].subVec[subclass] -> else entry[class].default;
default factory object at 0xac1118 (vtable 0x98d93c, create=0x7c7ff0 -> plain t_stationary_adventure_object).
Factory->create(name, &triple) = vtable[0] of the factory object.  Registration: 0x7c7b20(class, factory)
(86 sites, static-initialiser stubs) and 0x7c7c40(class, subclass, factory) (17 sites).
The class index is the enum below (from the adv_object classification name = first string of the
resource's classification triple, e.g. "random_town"). Subclass id (2nd u16 of the resource triple) matters only
for classes 4 (artifact: 124,166 = spell_artifact), 31 (4,5), 40 (5), 76 (school 0..7), 98 (treasure 0..3).
Class enum (index -> name; names from adv_object classification, indices anchored by FUN_00463630's table and RTTI):
0=abandoned_mine, 1=abbey, 2=academy, 3=arena, 4=artifact, 5=artifact_pile, 6=blacksmith, 7=blattner_stone, 8=border_gate, 9=border_guard, 10=bridge, 11=buoy, 12=campfire, 13=carryover_hero, 14=cartographer, 15=chain, 16=clover_field, 17=coliseum, 18=conservatory, 19=corpse, 20=creature_bank, 21=creature_dwelling, 22=decorative, 23=deletion_marker, 24=dolphin_school, 25=event_trigger, 26=exhausted_mine, 27=eye_of_the_magi, 28=faerie_ring, 29=ferry, 30=flotsam, 31=fountain, 32=garrison, 33=gateway, 34=hut_of_the_magi, 35=idol_of_fortune, 36=kelp_beds, 37=keymaster_tent, 38=lighthouse, 39=magic_gem, 40=mana_recharger, 41=material_pile, 42=medicine_wagon, 43=mercenary_camp, 44=mine, 45=movement_booster, 46=nothing, 47=obelisk, 48=obelisk_marker, 49=ocean_bottle, 50=outpost, 51=oyster, 52=pandoras_box, 53=path_arrow, 54=pathfinder, 55=port, 56=prison, 57=quest_gate, 58=quest_guard, 59=rainbow, 60=random_artifact, 61=random_creature_dwelling, 62=random_conservatory, 63=random_material_pile, 64=random_monster, 65=random_potion, 66=random_random_monster, 67=random_shrine, 68=random_staff, 69=random_teacher, 70=random_temple, 71=random_tome, 72=random_town, 73=random_weekly_material_generator, 74=sacred_grove, 75=sanctuary, 76=school, 77=seers_hut, 78=selection_ring, 79=ship, 80=shipwreck_survivor, 81=shipyard, 82=shrine, 83=sign, 84=sphinx, 85=stagecoach, 86=subterranean_gate, 87=system_object, 88=tavern, 89=teacher, 90=teleporter_entrance, 91=teleporter_exit, 92=temple, 93=unknown93, 94=tower, 95=town, 96=trading_post, 97=training_grounds, 98=treasure, 99=tree_of_knowledge, 100=vein, 101=victory_flag, 102=weekly_material_generator, 103=windmill, 104=whirlpool

Classes with NO registered factory (use default plain stationary object, reader = version-only): 1=abbey, 10=bridge, 22=decorative, 26=exhausted_mine, 36=kelp_beds, 46=nothing, 53=path_arrow, 78=selection_ring, 79=ship, 85=stagecoach, 87=system_object, 93=unknown93, 101=victory_flag.
(Index 93 name unknown; no model uses it.)

## 3. Class table  (class sub name | factory obj | create fn | ctor | most-derived class (RTTI) + primary vtable | reader = vtable[0x90])
Reader 0x4fa760 = "version-only": `u16 v; return v==0`.   Everything below that lists 0x4fa760 therefore has body = u16 0.
```
# class sub name | factory-obj | slot0(create) | ctor | primary-class(RTTI) vtable | reader(+0x90)
0 None abandoned_mine | 0x42365c | 0x427f60 | 0x423670 | t_adv_abandoned_mine 0x971a7c | 0x4263e0
2 None academy | 0x41a08c | 0x41a5a0 | 0x41a0a0 | t_academy 0x9712bc | 0x4fa760
3 None arena | 0x42edfc | 0x42f1c0 | 0x42ee10 | t_adv_arena 0x97218c | 0x4fa760
4 None artifact | 0x42f29c | 0x431ca0 | 0x42f300 | t_adv_artifact 0x97283c | 0x4fa760
4 124 artifact | 0x42f2ee | 0x431d10 | 0x4309f0 | t_adv_spell_artifact 0x9729d4 | 0x430e10
4 166 artifact | 0x42f2c1 | 0x431d10 | 0x4309f0 | t_adv_spell_artifact 0x9729d4 | 0x430e10
5 None artifact_pile | 0x43229c | 0x434b10 | 0x4322b0 | t_adv_artifact_pile 0x9731fc | 0x4fa760
6 None blacksmith | 0x43570c | 0x4385a0 | 0x436760 | t_adv_blacksmith 0x9735e4 | 0x4fa760
7 None blattner_stone | 0x75d91c | 0x75eb40 | inline | t_adv_blattner_stone 0x98b204 | 0x4fa760
8 None border_gate | 0x438dcc | 0x439440 | 0x438de0 | t_adv_border_gate 0x973aec | 0x4fa760
9 None border_guard | 0x43951c | 0x43a180 | 0x439530 | t_adv_border_guard 0x973c98 | 0x4fa760
11 None buoy | 0x75d8bc | 0x75e8e0 | inline | t_morale_object 0x98b064 | 0x4fa760
12 None campfire | 0x5aeb3c | 0x5af210 | 0x5aeb50 | t_campfire 0x97e8d4 | 0x4fa760
13 None carryover_hero | 0x5be89c | 0x5bf660 | 0x5beb70 | t_carryover_hero 0x97eb4c | 0x5bf4a0
14 None cartographer | 0x841a5c | 0x843ba0 | 0x842260 | t_cartographer 0x993c90 | 0x4fa760
15 None chain | 0x43a29c | 0x43a460 | 0x43a2b0 | t_adv_chain_link 0x973e44 | 0x4fa760
16 None clover_field | 0x75d7cc | 0x75e770 | 0x75d950 | t_luck_object 0x98aec4 | 0x4fa760
17 None coliseum | 0x43a64c | 0x43b980 | 0x43a660 | t_adv_coliseum 0x973fec | 0x4fa760
18 None conservatory | 0x43572c | 0x438610 | 0x437230 | t_adv_conservatory 0x973798 | 0x437560
19 None corpse | 0x4447dc | 0x444b80 | inline | t_adv_skeleton 0x975584 | 0x4fa760
20 None creature_bank | 0x6480ac | 0x64baf0 | 0x6485d0 | t_creature_bank 0x984f40 | 0x4fa760
21 None creature_dwelling | 0x43bf3c | 0x43f650 | 0x43c700 | t_adv_dwelling 0x974310 | 0x43c9c0
23 None deletion_marker | 0x44a71c | 0x44a7d0 | inline | t_adv_object_deletion_marker 0x97649c | 0x44a750
24 None dolphin_school | 0x75d7fc | 0x75e770 | 0x75d950 | t_luck_object 0x98aec4 | 0x4fa760
25 None event_trigger | 0x7dc35c | 0x7dc530 | inline | t_placed_event_trigger 0x98e56c | 0x44a750
27 None eye_of_the_magi | 0x444e2c | 0x444e60 | inline | t_adv_magi_eye 0x97572c | 0x4fa760
28 None faerie_ring | 0x75d82c | 0x75e770 | 0x75d950 | t_luck_object 0x98aec4 | 0x4fa760
29 None ferry | 0x43fe7c | 0x441180 | 0x43fe90 | t_adv_ferry 0x974814 | 0x44a750
30 None flotsam | 0x71afcc | 0x71b680 | 0x71afe0 | t_flotsam 0x9886ac | 0x4fa760
31 None fountain | 0x44178c | 0x4422b0 | 0x4417a0 | t_adv_fountain 0x974b4c | 0x4fa760
31 4 fountain | 0x75d85e | 0x75e770 | 0x75d950 | t_luck_object 0x98aec4 | 0x4fa760
31 5 fountain | 0x75d8ee | 0x75e8e0 | inline | t_morale_object 0x98b064 | 0x4fa760
32 None garrison | 0x44238c | 0x442d20 | inline | t_adv_garrison 0x974d34 | 0x7d3f60
33 None gateway | 0x72203c | 0x722e80 | 0x722050 | t_gateway 0x9889ac | 0x44a750
34 None hut_of_the_magi | 0x841a7c | 0x843d00 | 0x842990 | t_magi_hut 0x993e44 | 0x4fa760
35 None idol_of_fortune | 0x75d93c | 0x75ed90 | inline | t_adv_idol_of_fortune 0x98b3a4 | 0x4fa760
37 None keymaster_tent | 0x4430fc | 0x443990 | 0x443110 | t_adv_keymaster_tent 0x974ef0 | 0x4fa760
38 None lighthouse | 0x75bf4c | 0x75c4c0 | inline | t_lighthouse 0x98ac70 | 0x478a10
39 None magic_gem | 0x4450fc | 0x4458f0 | 0x445220 | t_adv_magic_gem 0x9758d4 | 0x4fa760
40 None mana_recharger | 0x778bfc | 0x77a150 | 0x778c10 | t_mana_source 0x98bd40 | 0x4fa760
40 5 mana_recharger | 0x445a2e | 0x4467b0 | 0x445a40 | t_adv_mana_vortex 0x975a7c | 0x4fa760
41 None material_pile | 0x790f8c | 0x791d80 | 0x7912b0 | t_material_pile 0x98c4a4 | 0x4fa760
42 None medicine_wagon | 0x44695c | 0x447c40 | 0x446970 | t_adv_medicine_wagon 0x975c28 | 0x4fa760
43 None mercenary_camp | 0x447f7c | 0x448350 | 0x447f90 | t_adv_mercenary_camp 0x975dd4 | 0x4fa760
44 None mine | 0x79c21c | 0x79e6a0 | 0x79c260 | t_mine 0x98ccec | 0x7d3f60
45 None movement_booster | 0x44842c | 0x4490b0 | 0x448460 | t_adv_move_booster 0x975f94 | 0x4fa760
47 None obelisk | 0x44927c | 0x44a5e0 | 0x449290 | t_adv_obelisk 0x9762f0 | 0x4fa760
48 None obelisk_marker | 0x7c682c | 0x7c6bd0 | inline | t_adv_obelisk_marker 0x98d804 | 0x7c6a80
49 None ocean_bottle | 0x46763c | 0x467810 | 0x467650 | t_adv_ocean_bottle 0x976984 | 0x46ddb0
50 None outpost | 0x88d4ec | 0x8a29a0 | inline | t_outpost 0x9960fc | 0x8a1260
51 None oyster | 0x75d79c | 0x75e770 | 0x75d950 | t_luck_object 0x98aec4 | 0x4fa760
52 None pandoras_box | 0x7dc37c | 0x7dc830 | inline | t_adv_object_pandoras_box 0x98e884 | 0x44a750
54 None pathfinder | 0x44844c | 0x449120 | 0x448d50 | t_adv_pathfinder 0x976138 | 0x4fa760
55 None port | 0x80ad9c | 0x80d0f0 | 0x80cd00 | t_sea_sanctuary 0x990ad0 | 0x4fa760
56 None prison | 0x4678ec | 0x468660 | 0x467900 | t_adv_prison 0x976b2c | 0x467f20
57 None quest_gate | 0x7ed15c | 0x7eff70 | inline | t_quest_gate 0x98f464 | 0x7eec70
58 None quest_guard | 0x7ed17c | 0x7f0280 | inline | t_quest_guard 0x98f60c | 0x7ef7e0
59 None rainbow | 0x75d88c | 0x75e770 | 0x75d950 | t_luck_object 0x98aec4 | 0x4fa760
60 None random_artifact | 0x43111c | 0x431d80 | 0x431130 | t_random_artifact 0x972b74 | 0x4fa760
61 None random_creature_dwelling | 0x43bf5c | 0x43f6c0 | 0x43f1c0 | t_random_adv_dwelling 0x974664 | 0x43f450
62 None random_conservatory | 0x43574c | 0x438680 | 0x437b80 | t_adv_random_conservatory 0x973940 | 0x437ea0
63 None random_material_pile | 0x790fac | 0x791ee0 | 0x791b30 | t_random_material_pile 0x98c63c | 0x4fa760
64 None random_monster | 0x7f329c | 0x7f4000 | inline | t_random_monster 0x98ff54 | 0x7f3710
65 None random_potion | 0x4318cc | 0x431ed0 | 0x4318e0 | t_random_potion 0x973054 | 0x4fa760
66 None random_random_monster | 0x7f327c | 0x7f3db0 | inline | t_random_random_monster 0x98fdb4 | 0x7f3710
67 None random_shrine | 0x46b10c | 0x46d2f0 | 0x46cd90 | t_random_adv_shrine 0x977394 | 0x46cfd0
68 None random_staff | 0x43163c | 0x431e60 | 0x431650 | t_random_staff 0x972eb4 | 0x4fa760
69 None random_teacher | 0x42d45c | 0x42ead0 | 0x42e2b0 | t_random_altar 0x971fe4 | 0x42e4b0
70 None random_temple | 0x47247c | 0x473d60 | 0x4738b0 | t_random_temple 0x9780dc | 0x473aa0
71 None random_tome | 0x4313ac | 0x431df0 | 0x4313c0 | t_random_tome 0x972d14 | 0x4fa760
72 None random_town | 0x7f506c | 0x7f5670 | 0x7f5080 | t_random_town 0x9901b4 | 0x7f52b0
73 None random_weekly_material_generator | 0x8cbcfc | 0x8cd200 | 0x8cce50 | t_random_weekly_generator 0x998288 | 0x8ccd70
74 None sacred_grove | 0x46877c | 0x468af0 | 0x468790 | t_adv_sacred_fountain 0x976cdc | 0x4fa760
75 None sanctuary | 0x80ad7c | 0x80d080 | 0x80adb0 | t_sanctuary 0x990860 | 0x4fa760
76 0 school | 0x765e0e | 0x767590 | 0x765e40 | t_magic_university 0x98b7ac | 0x766cd0
76 1 school | 0x765e2e | 0x7676f0 | 0x7672a0 | t_war_college 0x98b94c | 0x766cd0
76 2 school | 0x81930e | 0x81ab10 | 0x819340 | t_school_of_magic 0x990e34 | 0x81a1c0
76 3 school | 0x81932e | 0x81ab80 | 0x81a890 | t_school_of_war 0x990fdc | 0x81a1c0
76 4 school | 0x75ba4e | 0x75bc80 | 0x75ba60 | t_library 0x98aab4 | 0x8cb860
76 5 school | 0x8c9b0e | 0x8cba10 | 0x8c9c30 | t_war_institute 0x997efc | 0x8cb860
76 6 school | 0x58aaee | 0x58c660 | 0x58c360 | t_witch_hut 0x97d4b8 | 0x58c080
76 7 school | 0x58aace | 0x58c4e0 | 0x58ab00 | t_beastmaster_hut 0x97d31c | 0x58c080
77 None seers_hut | 0x7ed19c | 0x7f05b0 | inline | t_seers_hut 0x98f7b4 | 0x7efac0
80 None shipwreck_survivor | 0x44472c | 0x444880 | inline | t_adv_shipwreck_survivor 0x975254 | 0x4fa760
81 None shipyard | 0x469c8c | 0x46ada0 | inline | t_adv_shipyard 0x977044 | 0x478a10
82 None shrine | 0x46b0ec | 0x46d280 | 0x46b740 | t_adv_shrine 0x9771fc | 0x46c4a0
83 None sign | 0x46d82c | 0x46dfc0 | 0x46d950 | t_adv_sign 0x97753c | 0x46ddb0
84 None sphinx | 0x46e0dc | 0x46e530 | 0x46e0f0 | t_adv_sphinx 0x9776e4 | 0x4fa760
86 None subterranean_gate | 0x46e60c | 0x46f660 | 0x46e620 | t_adv_subterranean_gate 0x97789c | 0x44a750
88 None tavern | 0x47041c | 0x470f10 | 0x470430 | t_adv_tavern 0x977a44 | 0x4fa760
89 None teacher | 0x42d43c | 0x42ea60 | 0x42d4d0 | t_adv_altar 0x971e4c | 0x4fa760
90 None teleporter_entrance | 0x47104c | 0x471cf0 | 0x471060 | t_adv_teleporter_entrance 0x977bec | 0x44a750
91 None teleporter_exit | 0x471e2c | 0x472340 | 0x471e40 | t_adv_teleporter_exit 0x977d94 | 0x44a750
92 None temple | 0x47245c | 0x473cf0 | 0x472490 | t_adv_temple 0x977f44 | 0x4fa760
94 None tower | 0x841a9c | 0x843e60 | 0x843500 | t_tower 0x993fec | 0x4fa760
95 None town | 0x88d4cc | 0x8a2930 | 0x893980 | t_town 0x995f4c | 0x89a710
96 None trading_post | 0x473e3c | 0x474350 | 0x473e50 | t_adv_trading_post 0x978284 | 0x4fa760
97 None training_grounds | 0x47440c | 0x4747d0 | 0x474420 | t_adv_training_grounds 0x97842c | 0x4fa760
98 0 treasure | 0x44479e | 0x444a00 | inline | t_adv_travelers_backpack 0x9753ec | 0x4fa760
98 1 treasure | 0x443c5e | 0x444810 | 0x443c70 | t_adv_mages_chest 0x9750a4 | 0x4fa760
98 2 treasure | 0x4748ae | 0x475890 | 0x4748c0 | t_adv_treasure_chest 0x9785e4 | 0x4fa760
98 3 treasure | 0x468bce | 0x469b50 | 0x468be0 | t_adv_sea_chest 0x976e94 | 0x4fa760
99 None tree_of_knowledge | 0x4759ac | 0x476f10 | 0x4759c0 | t_adv_tree_of_knowledge 0x97878c | 0x4fa760
100 None vein | 0x79c23c | 0x79e710 | 0x79da70 | t_adv_vein 0x98ce94 | 0x4fa760
102 None weekly_material_generator | 0x8cbcdc | 0x8cd190 | 0x8cbfb0 | t_weekly_generator 0x9980e8 | 0x8ccd70
103 None windmill | 0x477cbc | 0x478bb0 | 0x477cd0 | t_adv_windmill 0x978b14 | 0x478a10
104 None whirlpool | 0x476fec | 0x477a80 | 0x477000 | t_adv_whirlpool 0x97894c | 0x44a750
```
Note: for rows marked `inline` the constructor is inlined in the create function; the vtable shown is the last
store to `this` (most derived). Objects share readers: 0x44a750 (gateway family), 0x478a10 (owned_scriptable family),
0x7d3f60 (garrison, mine), 0x766cd0 / 0x81a1c0 / 0x8cb860 / 0x58c080 (school variants).

## 4. Reader layouts

### 4.1 Version-only [V]   (reader 0x4fa760; classes listed above with 0x4fa760, incl. decorative=22 default factory)
```
u16 version == 0
```
Validated: 12199 decorative, creature_bank, artifacts, random_artifact, etc. over all maps.

### 4.2 Gateway family / event family [V partially]   reader 0x44a750
classes: ferry 29, gateway 33, subterranean_gate 86, teleporter_entrance 90, teleporter_exit 91, whirlpool 104,
deletion_marker 23, event_trigger 25, pandoras_box 52  (the last three: t_placed_event_base; additional event data is NOT in this record)
```
u16 version (0 or 1)     -- other values => failure
if version == 1: str16 name        (FUN_00879420)
```
Validated for teleporters/gateways/whirlpools (ver 0 seen). Same reader also used for ocean_bottle 49 / sign 83 (0x46ddb0) [V]: `u16 ver (0..1); if ver==1: str16 message`.

### 4.3 obelisk_marker (48) reader 0x7c6a80 [D]
```
u16 version (0 or 1);  if version >= 1: u16 value
```
### 4.4 outpost (50) reader 0x8a1260 [D]
```
u16 version (0 or 1);  if version == 1: u8 owner (must be < 7)
```
### 4.5 owned_scriptable family: lighthouse 38, shipyard 81, windmill 103 (reader 0x478a10 -> 0x7d7270) [V for count==0]
```
u16 version (0..2)
if version >= 1: u8 owner (<7)     else owner = 6 (neutral)            -- stored at +0x4c
if version >= 2: FUN_007d7590: u16 n ; n x script_object (0x50 bytes, vtable 0x971190, read by FUN_007d3530)  [element layout ?]
```
Real data: lighthouse bytes `02 00 | 06 | 00 00` = ver 2, owner 6 (neutral), n=0.
(t_owned_scriptable_adv_object base is also used by creature_dwelling 21 (reader 0x43c9c0), random dwelling 61, weekly generators 102/73, quest sites.)

### 4.6 ownable garrisonable: garrison 32, mine 44 (reader 0x7d3f60 -> 0x7d3fb0) [D]
```
u16 version (<= 2)
if version >= 1: u8 owner (<7) else owner=6
if version >= 2 and owner != 6: u8 flag(bool) else flag = 1
if version >= 2:
    4 x FUN_007d2fd0 (objects at this+0x9c..)           -- 7d2fd0: u16 ver(<=0), FUN_00705e20 ..., loops of u8 (7x) and u8 (2x): looks like per-player/flag arrays   [?]
    FUN_007d4150, FUN_007d4390, FUN_007d45c0           -- each: u16 count + count x script/event objects (FUN_007d37f0 / 7d3290 / 7d3530)  [?]
    u8 hasArmy ; if hasArmy: FUN_00640d00(stream) on this+0x54 (army: u16 count<=7?, 7 slots) else clear army   [?]
```
Mine adds nothing after this (t_mine uses the same slot; extra mine-specific data not read here). OPEN: exact byte layout of 7d2fd0/7d4150/7d4390/7d45c0/640d00 (not yet traced);
mines (24 in shipped maps) and towns (39) are the first blockers in 70% of maps.

### 4.7 Town (95) reader 0x89a710 (401 insns), random_town (72) reader 0x7f52b0   [?]
Real bytes after the triple of a random_town (Gold Rush):
`07 00 | 00 00 | 06 00 "player" | 01 08 00 01 00 00 00 01 0a 10 00 00 00 00 bf ff ff ff ff 07 00 00 | 02 00 03 00 "seq" 00 ... (many zero bytes)`
=> body starts with u16 version (7 here), then owner/name fields and building/garrison data, with repeated
`02 00 03 00 "seq"` subrecords (each followed by ~0x20 zeros then `7f 03 00 00`). Not decoded.

### 4.8 Other non-trivial readers (addresses to trace next)  [?]
artifact spell_artifact 430e10; carryover_hero 5bf4a0; conservatory 437560; random_conservatory 437ea0;
creature_dwelling 43c9c0 (vtable 0x974310) ; random_creature_dwelling 43f450; prison 467f20; shrine 46c4a0;
random_shrine 46cfd0; random_teacher 42e4b0; random_temple 473aa0; random_monster/random_random_monster 7f3710;
school variants 766cd0 (univ/war college) 81a1c0 (school of magic/war) 8cb860 (library, war institute) 58c080 (witch hut, beastmaster);
weekly_material_generator 8ccd70 (random_weekly 8ccd70 too); sanctuary: t_sanctuary primary vtable 0x990860 -> 0x4fa760 but
secondary 0x80b610; quest_gate 7eec70; quest_guard 7ef7e0; seers_hut 7efac0 (quest objects have their own readers);
abandoned_mine 4263e0 (ver<=1, uses 7d2fd0, 426510, 426750, 426970, 640d00, 425340); t_army 523a30 (flag!=0 records).
Helpers: 7d2fd0, 7d3530, 7d37f0, 7d3290, 7d4150, 7d4390, 7d45c0, 7d7590, 640d00.

## 5. Validation harness
python/chain.py : walk() parses the list from the first plausible record with the readers above; allmaps.py runs all shipped
maps. Current result: all records up to the first non-implemented class parse and chain exactly (17,950 records over
105 maps, 0 desyncs; first blockers: town 39 maps, random_town 28, mine 24, weekly_material_generator 6, shrine/dwelling/monster/school/sanctuary/army 1-3 each).
Files: chain.py cls.py allmaps.py regs.py fac.py slot0.py readers.py primary.py trace.py asm.py asm2.py classtable.txt text.asm(heroes4 disasm) heroes4.exe(copy)

## 6. Open questions
- t_army (flag != 0) layout (0x523a30) and the shared army reader 0x640d00.
- Town / random town (0x89a710 / 0x7f52b0) incl. buildings, name, garrison, hero-visiting data, "seq" subrecords.
- 0x7d2fd0 etc. (script/event member layout) - used by garrison, mine, abandoned_mine, dwelling.
- Meaning/validity checks of the mismatch between file ids and registry ids (resolved by name via tables at 0xa8f55c, 0x2c bytes/entry).
