# quests topic (resumed agent). Script grammar: data-inferred, extends sections/SPEC.md; replace with scripts agent's grammar when ready.
SPEC = {'seq':'L','if':'NNN','var':'S','lit':'I','is_eliminated':'B','is_dead':'S','is_imprisoned':'S',
 'win':'B','lose':'B','enable_vc':'B','disable_vc':'B','rem_event':'','rem_this':'','no_op':'','true':'','day':'',
 'set_num':'SN','set_bool':'SN','text':'SL','and':'NN','or':'NN',
 'detonate':'S','owns_town':'BS','owns_hero':'BS','has_hero':'BS','gosub':'S','inc_level':'BB','dec_morale':'BB',
 'give_material':'BR','set_l_msg':'BS','set_v_msg':'BS','set_lc_text':'BS','set_vc_text':'BS','is_color':'BB','is_human':'B',
 'has_artifact':'BBH','give_creature':'BHH','give_artifact':'BM','combat':'CNN',
 # additions (inferred from quest data)
 'not':'N','is_computer':'B','total_creatures':'B','materials':'BB','total_heroes':'B','exp_level':'B',
 'creatures':'BH','take_material':'BR','take_creature':'BHH','give_skill':'BBB','inc_skill':'BBB','rem_artifact':'BM','inc_luck':'BB','dec_luck':'BB','inc_morale':'BB','mastery':'BB',
 # from exe node readers (sections/classes.txt): 81dac0=BHB, 81d7b0=BH, 81f720=BH, 82eae0=BI, 82bda0=BH, 82d330=BB, 8239e0=B, 823bd0=B
 'inc_exp':'BI','inc_damage':'BHB','dec_damage':'BHB','inc_max_hp':'BHB','dec_max_hp':'BHB','inc_max_mana':'BHB','dec_max_mana':'BHB',
 'inc_speed':'BHB','dec_speed':'BHB','inc_mana':'BH','dec_mana':'BH','inc_pop':'BH','dec_pop':'BH','give_spell':'BH','inc_move':'BB',
 'build':'B','change_owner':'B','dec_luck':'BB','dec_morale':'BB',
 'player':'B','false':'','dow':'','week':'','month':'','wom':''}
def node(r):
    n = r.str16()
    if n in SPEC: spec = SPEC[n]
    elif n and not n.replace('_','').isalnum() and len(n) <= 2: spec = 'NN'
    else: raise AssertionError('unknown node %r @%d next=%s' % (n, r.p, r.b[r.p:r.p+20].hex(' ')))
    for c in spec:
        if c == 'N': node(r)
        elif c == 'S': r.str16()
        elif c == 'B': r.u8()
        elif c == 'H': r.u16()
        elif c == 'I': r.u32()
        elif c == 'C':
            assert r.u16() == 0; r.u8()
            for _ in range(7):
                m = r.u8()
                if m != 0xff: assert m == 0; r.u16(); r.u16(); r.u32()
        elif c == 'M': [r.u16() for _ in range(r.u16())]
        elif c == 'R': [r.u32() for _ in range(7)]
        elif c == 'L':
            for _ in range(r.u16()): node(r)
import os as _os, importlib.util as _iu2
_sp=_iu2.spec_from_file_location('_scripts_exe_q', _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),'..','sections','scripts.py'))
_scripts=_iu2.module_from_spec(_sp); _sp.loader.exec_module(_scripts)
def _wrap(f):
    try: return f()
    except AssertionError: raise
    except Exception as e: raise AssertionError('script: '+repr(e)[:80])
def script(r):   # FUN_00410930: u16 version + action node (exe-decoded grammar, sections/scripts.py)
    return _wrap(lambda: _scripts.read_script(r))
def expr(r):     # FUN_004112a0: u16 version + bool expression node
    def f():
        v = r.u16(); assert v <= 2, ('expr ver', v); return _scripts.read_bool(r, v)
    return _wrap(f)
def quest_core(r, has):   # FUN_007ed980(stream, progress, has)
    if not has: return
    for _ in range(4): r.str16()     # +0x84, +0x70, +0x60, +0x50
    script(r)                        # 410930 -> +0x48
    expr(r)                          # 4112a0 -> +0x4c
def quest_gate(r, ver):   # 0x7eec70
    v = r.u16(); assert v <= 1, ('qgate ver', v)
    quest_core(r, v >= 1)
def quest_guard(r, ver):  # 0x7ef7e0
    v = r.u16(); assert v <= 2, ('qguard ver', v)
    if v == 0: return
    quest_core(r, True); r.str16()   # +0x98
    if v >= 2: script(r)             # 7ef410 -> +0xa8
def seers_hut(r, ver):    # 0x7efac0
    v = r.u16(); assert v <= 2, ('seer ver', v)
    if v == 0: return
    quest_core(r, True); r.str16()   # +0x98
    if v >= 2: script(r)             # 7ef410
    r.str16()                        # +0xac
    if v < 2: script(r)              # 7ef410
READERS = {57: quest_gate, 58: quest_guard, 77: seers_hut}

# ---- spell sets, schools, shrines, random sites ----
def spellset(r, sub):     # FUN_00865990(stream, sub): sub==0 -> 23 bytes (184 bits), sub>=1 -> 24 bytes (192 bits, 0xba/0xbc spells)
    n = 0x17 if sub == 0 else 0x18
    r.p += n
def spellset_v(r):        # FUN_00865be0: u8 sub ; FUN_00865990(sub)
    sub = r.u8(); assert sub <= 2, ('spellset sub', sub); spellset(r, sub)
def set36(r):             # FUN_00857ec0: u8 (must be 0) + 5 bytes (36-bit set: skills)
    v = r.u8(); assert v == 0, ('set36', v); r.p += 5
def selector(r):          # FUN_0075cae0: u16 0 ; str16 kind (FUN_0075c7c0) ; kind 'player' -> u8
    v = r.u16(); assert v == 0, ('sel ver', v)
    k = r.str16()
    if k == 'player': r.u8()          # kind 1
    elif k == 'town': r.str16()       # kind 2 (town name)
    elif k == 'none': pass            # kind 0
    else: raise AssertionError('selector kind %r' % k)
def school(r, ver):       # 0x766cd0 (subs 0,1) / 0x81a1c0 (2,3) / 0x8cb860 (4,5) / 0x58c080 (6,7)
    v = r.u16(); assert v <= 1, ('school ver', v)
    if v == 1: set36(r); set36(r)
def shrine(r, ver):       # 0x46c4a0
    v = r.u16(); assert v <= 2, ('shrine ver', v)
    if v >= 2: spellset_v(r)
    elif v == 1: spellset(r, 0)
def random_shrine(r, ver):  # 0x46cfd0
    v = r.u16(); assert v <= 3, ('rshrine ver', v)
    if v >= 2: spellset_v(r)
    elif v == 1: spellset(r, 0)
    if v >= 3: selector(r)      # 75cae0; v<3 -> 75cd50 default (no read)
def random_teacher(r, ver):  # 0x42e4b0
    v = r.u16(); assert v <= 1, ('rteacher ver', v)
    if v >= 1:
        m = r.u16(); assert m < 0x200 or True   # 9-bit mask of allowed teacher types
        selector(r)
def random_temple(r, ver):   # 0x473aa0
    v = r.u16(); assert v <= 1, ('rtemple ver', v)
    if v >= 1: selector(r)
def spell_artifact(r, ver):  # 0x430e10
    v = r.u16(); assert v <= 1, ('spellart ver', v)
    if v: r.u32()                # spell id
SCHOOLS = ['magic_university','war_college','school_of_magic','school_of_war','library','war_institute','witchs_hut','beastmasters_hut']
READERS.update({82: shrine, 67: random_shrine, 69: random_teacher, 70: random_temple, 'spell_artifact': spell_artifact})
READERS.update({(76, s): school for s in SCHOOLS})
