import sys
# --- script nodes (inferred grammar, copied from sections/parse_sections.py) ---
SPEC = {'seq':'L','if':'NNN','var':'S','lit':'I','is_eliminated':'B','is_dead':'S','is_imprisoned':'S',
 'win':'B','lose':'B','enable_vc':'B','disable_vc':'B','rem_event':'','rem_this':'','no_op':'','true':'','day':'',
 'set_num':'SN','set_bool':'SN','text':'SH','and':'NN','or':'NN',
 'detonate':'S','owns_town':'BS','owns_hero':'BS','has_hero':'BS','gosub':'S','inc_level':'BB','dec_morale':'BB',
 'give_material':'BR','set_l_msg':'BS','set_v_msg':'BS','set_lc_text':'BS','set_vc_text':'BS','is_color':'BB','is_human':'B',
 'has_artifact':'BBH','give_creature':'BHH','give_artifact':'BM','combat':'CNN'}
def node(r):
    n = r.str16()
    if n in SPEC: spec = SPEC[n]
    elif not n.replace('_','').isalnum() and len(n) <= 2: spec = 'NN'
    else: raise AssertionError('unknown script node '+n)
    for c in spec:
        if c == 'N': node(r)
        elif c == 'S': r.str16()
        elif c == 'B': r.u8()
        elif c == 'H': r.u16()
        elif c == 'C':
            assert r.u16() == 0; r.u8()
            for _ in range(7):
                m = r.u8()
                if m != 0xff:
                    assert m == 0; r.u16(); r.u16(); r.u32()
        elif c == 'M': [r.u16() for _ in range(r.u16())]
        elif c == 'R': [r.u32() for _ in range(7)]
        elif c == 'I': r.u32()
        elif c == 'L':
            for _ in range(r.u16()): node(r)
import os as _os, importlib.util as _iu2
_sp=_iu2.spec_from_file_location('_scripts_exe', _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),'..','sections','scripts.py'))
_scripts=_iu2.module_from_spec(_sp); _sp.loader.exec_module(_scripts)
def Z(r):  # FUN_00827ef0 -> exe-decoded grammar (sections/scripts.py)
    try: return _scripts.read_script(r)
    except AssertionError: raise
    except Exception as e: raise AssertionError('script: '+repr(e)[:80])
def Zs(r): # FUN_0063bda0
    Z(r); r.str16()
def Y(r):  # FUN_00705e20
    Z(r); r.str16(); [r.u32() for _ in range(7)]
def Ys(r): # FUN_008c8db0
    Y(r); r.str16()
def X(r):  # FUN_0088c700
    Y(r); r.str16(); r.u16(); r.u16()
def rec_2fd0(r):   # FUN_007d2fd0
    assert r.u16()==0; Y(r); r.u8(); r.u8()
def rec_37f0(r):   # FUN_007d37f0
    assert r.u16()==0; Zs(r); r.u8(); r.u8(); r.u8()
def rec_3290(r):   # FUN_007d3290
    assert r.u16()==0; X(r); r.u8(); r.u8()
def rec_3530(r):   # FUN_007d3530  (script_object)
    assert r.u16()==0; Ys(r); r.u8(); r.u8()
def lst(r, f):
    for _ in range(r.u16()): f(r)
_ARMY=None
def army640d00(r):  # FUN_00640d00 -> ext_army.army_stacks (army topic)
    global _ARMY
    if _ARMY is None:
        import importlib.util, os
        p=os.path.join(os.path.dirname(os.path.abspath(__file__)),'ext_army.py')
        sp=importlib.util.spec_from_file_location('ext_army_for_ownables',p); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
        _ARMY=m.army_stacks
    _ARMY(r)
def owned(r, v):    # FUN_007d7270(stream, ver) -> sets owner, FUN_007d7590
    if v >= 1:
        o = r.u8(); assert o < 7
    if v >= 2: lst(r, rec_3530)
def mine_garrison(r, ver):   # 0x7d3f60 -> 0x7d3fb0
    v = r.u16(); assert v <= 2
    if v == 0: owner = 6
    else:
        owner = r.u8(); assert owner <= 6
    if not (v < 2 or owner == 6): r.u8()
    if v >= 2:
        for _ in range(4): rec_2fd0(r)
        lst(r, rec_37f0); lst(r, rec_3290); lst(r, rec_3530)
        if r.u8(): army640d00(r)
def abandoned_mine(r, ver):  # 0x4263e0
    v = r.u16(); assert v <= 1
    if v:
        for _ in range(4): rec_2fd0(r)
        lst(r, rec_37f0); lst(r, rec_3290); lst(r, rec_3530)
        if r.u8(): army640d00(r)
def owned_scriptable(r, ver):  # 0x478a10 / 0x43c9c0 / 0x8ccd70 (v<=2)
    v = r.u16(); assert v <= 2; owned(r, v)
def bitset_865be0(r):
    v = r.u8(); r.b[r.p:r.p+0x17 if v == 0 else 0x18]; r.p += 0x17 if v == 0 else 0x18
def spec_75cae0(r):
    assert r.u16() == 0
    k = r.str16()
    if k == 'player': r.u8()
    elif k == 'town': r.str16()
def random_dwelling(r, ver):   # 0x43f450
    v = r.u16(); assert v <= 3
    owned(r, 0 if v == 0 else (2 if v >= 3 else 1))
    if v >= 2: spec_75cae0(r)
def conservatory(r, ver):      # 0x437560
    v = r.u16(); assert v <= 1
    if v == 1: bitset_865be0(r); bitset_865be0(r)
def random_conservatory(r, ver):  # 0x437ea0
    v = r.u16(); assert v <= 2
    if v == 2: bitset_865be0(r); bitset_865be0(r)
    if v >= 1: spec_75cae0(r)
READERS = {44: mine_garrison, 32: mine_garrison, 0: abandoned_mine, 21: owned_scriptable, 61: random_dwelling,
           102: owned_scriptable, 73: owned_scriptable, 18: conservatory, 62: random_conservatory,
           38: owned_scriptable, 81: owned_scriptable, 103: owned_scriptable}
