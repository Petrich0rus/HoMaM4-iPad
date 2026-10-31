"""Town (95, t_town reader 0x89a710) and random_town (72, t_random_town reader 0x7f52b0) payload readers.
See SPEC_towns.md. r = chain.R (u8/u16/u32/str16, .b bytes, .p pos)."""
import struct
class Bad(AssertionError): pass
def chk(c, m):
    if not c: raise Bad(m)
def raw(r, n): v = r.b[r.p:r.p+n]; chk(len(v) == n, 'eof'); r.p += n; return v
def i16(r): v = struct.unpack_from('<h', r.b, r.p)[0]; r.p += 2; return v

# ---- script expression nodes (grammar from sections/SPEC.md, inferred from data; class table not decompiled) ----
# statements: factory table DAT_00a8d8c8 (54, registered via FUN_004111f0), name table init FUN_0081c390, read = vtable+0x10
# numeric exprs: table DAT_00ad4260 (21, FUN_00411290, names FUN_00828000); boolean exprs: DAT_00ad4200 (24, FUN_00411330,
# names FUN_008286b0); expression read = (heuristic create-vtable)+0x24. Codes: B u8, H u16, I u32, S str16, N child node,
# L u16 n + n nodes, R 7 x u32, M u16 n + n x u16, C combat (u8 kind<3 + army FUN_00640d00).
STMT = {'build':'B','change_owner':'B','clear_lc_text':'B','clear_l_msg':'B','clear_vc_text':'B','clear_v_msg':'B',
 'combat':'CNN','if':'NNN','dec_mana':'BH','dec_damage':'BHB','dec_luck':'BB','dec_max_hp':'BHB','dec_max_mana':'BHB',
 'dec_morale':'BB','dec_pop':'BH','dec_speed':'BHB','detonate':'S','disable_vc':'B','text':'SL','enable_vc':'B',
 'give_artifact':'BM','give_creature':'BHH','give_material':'BR','give_skill':'BBB','give_spell':'BH','inc_move':'BB',
 'inc_mana':'BH','inc_damage':'BHB','inc_exp':'BI','inc_level':'BB','inc_luck':'BB','inc_max_hp':'BHB','inc_max_mana':'BHB',
 'inc_morale':'BB','inc_pop':'BH','inc_skill':'BBB','inc_speed':'BHB','no_op':'','lose':'B','ask':'SNN','rem_event':'',
 'rem_this':'','seq':'L','set_bool':'SN','set_lc_text':'BS','set_l_msg':'BS','set_num':'SN','set_vc_text':'BS',
 'set_v_msg':'BS','rem_artifact':'BM','take_creature':'BHH','take_material':'BR','gosub':'S','win':'B'}
NUM = {'creatures':'BH','day':'','dow':'','/':'NN','exp_level':'B','mastery':'BB','lit':'I','materials':'BB','-':'NN',
 'month':'','neg':'N','player':'B','+':'NN','rand':'II','%':'NN','*':'NN','total_creatures':'B','total_heroes':'B',
 'var':'S','week':'','wom':''}
BOOL = {'and':'NN','has_alignment':'BB','has_hero':'BS','==':'NN','false':'','>':'NN','>=':'NN','has_artifact':'BBH',
 'is_dead':'S','is_imprisoned':'S','<':'NN','<=':'NN','not':'N','or':'NN','is_alignment':'BB','is_color':'BB',
 'is_computer':'B','is_eliminated':'B','is_human':'B','owns_hero':'BS','owns_town':'BS','true':'','var':'S'}
NODE = dict(NUM); NODE.update(BOOL); NODE.update(STMT)
def node(r):
    n = r.str16()
    if n in NODE: spec = NODE[n]
    elif n and not n.replace('_', '').isalnum() and len(n) <= 2: spec = 'NN'
    else: raise Bad('unknown script node %r' % n)
    for c in spec:
        if c == 'N': node(r)
        elif c == 'S': r.str16()
        elif c == 'B': r.u8()
        elif c == 'H': r.u16()
        elif c == 'I': r.u32()
        elif c == 'R': [r.u32() for _ in range(7)]
        elif c == 'M': [r.u16() for _ in range(r.u16())]
        elif c == 'L': [node(r) for _ in range(r.u16())]
        elif c == 'C':     # combat (stmt reader 0x824140): u8 kind (<3), army FUN_00640d00, then N win, N lose
            k = r.u8(); chk(k < 3, 'combat kind'); army(r)
import os as _os, importlib.util as _iu2
_sp=_iu2.spec_from_file_location('_scripts_exe_t', _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),'..','sections','scripts.py'))
_scripts=_iu2.module_from_spec(_sp); _sp.loader.exec_module(_scripts)
def Z(r):  # FUN_00827ef0 -> exe-decoded grammar (sections/scripts.py)
    try: return _scripts.read_script(r)
    except AssertionError: raise
    except Exception as e: raise AssertionError('script: '+repr(e)[:80])
def Y(r):  # FUN_00705e20: Z, str16, 7 x u32
    Z(r); r.str16(); [r.u32() for _ in range(7)]
def masks(r):  # u8 player mask (7 bits, FUN_0048bfc0), u8 flag mask (2 bits, FUN_00727240)
    r.u8(); r.u8()
def ev_trigger4(r):   # FUN_007d2fd0: u16 ver==0, Y, masks
    chk(r.u16() == 0, '7d2fd0 ver'); Y(r); masks(r)
def ev_timed(r):      # FUN_007d3290: u16 0, X(=FUN_0088c700: Y, str16, u16, u16), masks
    chk(r.u16() == 0, '7d3290 ver'); Y(r); r.str16(); r.u16(); r.u16(); masks(r)
def ev_triggerable(r):# FUN_007d3530: u16 0, FUN_008c8db0(Y, str16), masks
    chk(r.u16() == 0, '7d3530 ver'); Y(r); r.str16(); masks(r)
def ev_continuous(r): # FUN_007d37f0: u16 0, FUN_0063bda0(Z, str16), u8 bool, masks
    chk(r.u16() == 0, '7d37f0 ver'); Z(r); r.str16(); r.u8(); masks(r)
def counted(r, f):
    for _ in range(r.u16()): f(r)

# ---- army (FUN_00640d00) ----
def artifact(r):      # FUN_00664640 (one carried artifact)
    a = i16(r); chk(-1 <= a <= 0xf8, 'artifact id')
    if a in (0xa6, 0x7c): s = r.u16(); chk(s <= 0xbc, 'spell')
def stack_base(r):    # FUN_00653760: u16 n, n x artifact
    for _ in range(r.u16()): artifact(r)
def creature_stack(r):# vtable 0x98469c +0xd4 = FUN_0063e0f0
    v = r.u16(); chk(v <= 1, 'stack ver')
    c = i16(r); chk(c == -1 or 0 <= c < 0x4a, 'creature id'); i16(r)
    if v >= 1: stack_base(r)
def hero(r):          # vtable 0x989310 +0xd4 = FUN_0072f4e0
    hv = r.u16(); chk(8 <= hv <= 10, 'hero ver %d' % hv)
    t = i16(r); chk(t >= -1, 'hero id')        # FUN_0057fd40; < FUN_0073bb20() count (not checked here)
    r.u8()                                     # -> FUN_00729750 (sets +0x638: -1 or 0..0x2f)
    g = r.u8(); chk(g in (0, 1, 0xff), 'hero +0x634')
    r.u8()                                     # hv>=5: +0x6a0
    if hv >= 10: r.u8(); r.u8()                # stat bonuses (hv<10: two u16)
    else: r.u16(); r.u16()
    r.u8(); r.u8()
    r.str16(); r.str16()                       # name (+0x5b4), biography (+0x6a8)
    if r.u8():                                 # hv>=3: custom skills
        for _ in range(36):
            k = r.u8(); chk(k == 0xff or k < 5, 'skill level')
    bset188(r)                                 # hv>=4: FUN_00865be0 (+0x780)
    for _ in range(14):                        # FUN_0072f940 (hv>=2): 14 equipment slots
        if r.u8(): artifact(r)
    stack_base(r)                              # hv>=1: FUN_00653760 backpack artifacts
    for _ in range(3): ev_trigger4(r)          # FUN_00738700
    counted(r, ev_timed)                       # FUN_00738830 -> 738890
    counted(r, ev_triggerable)                 # FUN_00738850 -> 738af0
    counted(r, ev_continuous)                  # FUN_00738870 -> 738d50
    if hv >= 9: r.u8()                         # +0xa4
def army_slot(r):     # FUN_00640b50: i8 kind: -1 empty (0x428da0 reads nothing), 0 creature, 1 hero, other -> fail
    k = r.u8()
    if k == 0xff: return
    if k == 0: return creature_stack(r)
    if k == 1: return hero(r)
    raise Bad('army slot kind %d' % k)
def army(r):          # FUN_00640d00: u16 ver==0, 7 slots
    chk(r.u16() == 0, 'army ver')
    for _ in range(7): army_slot(r)

# ---- town shared ----
def bset188(r):       # FUN_00865be0: u8 ver; 0 -> 23 bytes (old 184-bit ids remapped), 1/2+ -> 24 bytes (188 bits)
    v = r.u8(); raw(r, 23 if v == 0 else 24)
def set36(r):         # FUN_00857ec0: u8 ver==0 + 5 bytes
    chk(r.u8() == 0, '857ec0 ver'); raw(r, 5)
def abstract_town(r, v):  # FUN_00417990 (v = 6..8)
    chk(6 <= v <= 8, 'abstract town ver %d' % v)
    o = r.u8(); chk(o < 7, 'owner')
    r.str16()                                  # FUN_00417f70 (v>=2): name
    if r.u8(): army(r)                         # v>=2 hasGarrison
    if r.u8(): raw(r, 6); raw(r, 6)            # FUN_00417c10 (v>=3): custom buildings: 43-bit present + 43-bit ... 
    else: r.u8()
    for _ in range(4): ev_trigger4(r)          # FUN_00417e40
    counted(r, ev_timed)                       # FUN_00418080
    counted(r, ev_triggerable)                 # FUN_004182f0
    counted(r, ev_continuous)                  # FUN_00418550
    if v >= 7:
        if r.u8(): set36(r); set36(r)
    if v >= 8: r.u8()                          # -> +0xa0
def abstract_town_ver(r):  # FUN_00417900: u16 v (6..8) then 417990
    v = r.u16(); chk(6 <= v <= 8, '417900 ver %d' % v); abstract_town(r, v)

def town(r, ver):     # 0x89a710
    v = r.u16(); chk(v <= 4, 'town ver %d' % v)
    chk(v == 4, 'town ver<4 passes v<6 to 417990 -> fail')
    bset188(r); bset188(r)
    abstract_town_ver(r)
RT_TYPES = ['none', 'player', 'town']
def random_town(r, ver):  # 0x7f52b0
    v = r.u16(); chk(v <= 7, 'rtown ver %d' % v)
    if v == 7:
        chk(r.u16() == 0, '75cae0 ver')         # FUN_0075cae0
        t = r.str16(); chk(t in RT_TYPES, 'rtown type %r' % t)
        if t == 'player': r.u8()
        elif t == 'town': r.str16()
        abstract_town_ver(r)
    else:
        abstract_town(r, v)
READERS = {95: town, 72: random_town}
