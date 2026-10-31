"""HoMM4 script-expression grammar, decoded from heroes4.exe (see SPEC_scripts.md).

r: reader with u8/u16/u32/raw and str16 (chain.R) or str (hdr.R).
read_script(r)      -> Z (FUN_00827ef0/00410930): u16 scriptVer + action node
read_node(r, ver)   -> one action node (FUN_004109a0 -> 00410b80, node vt+0x10)
read_num(r, ver)    -> numeric expression (FUN_00411230 -> 004114e0, vt+0x24)
read_bool(r, ver)   -> boolean expression (FUN_004112d0 -> 00411800, vt+0x24)
read_header_cine(r) -> scenario-header victory/defeat block (FUN_00816970)
read_event_obj(r)   -> object-embedded event (FUN_007d3530)
Nodes are returned as tuples (name, fields...). Raises ScriptError on any check the game makes.
"""
import struct

class ScriptError(Exception): pass
def chk(c, msg):
    if not c: raise ScriptError(msg)

def _s(r):
    f = getattr(r, 'str16', None) or getattr(r, 'str')
    return f()
def _i32(r):
    v = r.u32(); return v - (1 << 32) if v & 0x80000000 else v
def _h16(r):
    v = r.u16(); return v - 0x10000 if v & 0x8000 else v
def _b(r, lim, what):
    v = r.u8(); chk(v < lim, f'{what} {v} >= {lim}'); return v

# ---- shared sub-records -------------------------------------------------------
def player(r, ver):          # FUN_00830140 / FUN_004f0ec0 pattern: ver>=2 u8<9, else u8<8 (remapped by game)
    return _b(r, 9 if ver >= 2 else 8, 'player')
def hero_sel(r):             # u8 < 10
    return _b(r, 10, 'hero selector')

def artifact(r):             # FUN_00664640
    a = r.u16(); chk(a <= 0xf8, f'artifact id {a}')
    if a in (0xa6, 0x7c):    # spell scroll / potion-like: u16 spell
        s = r.u16(); chk(s <= 0xbc, f'artifact spell {s}'); return (a, s)
    return (a,)

def creature_stack(r):       # FUN_0063e0f0 (vt+0xd4 of stack class ctor FUN_0063cf80)
    v = r.u16(); chk(v <= 1, f'stack ver {v}')
    c = _h16(r); chk(c == -1 or 0 <= c < 74, f'creature {c}')
    n = _h16(r); arts = []
    if v >= 1:               # FUN_00653760
        arts = [artifact(r) for _ in range(r.u16())]
    return ('stack', c, n, arts)

def army(r):                 # FUN_00640d00: u16 ver==0; 7 x slot (FUN_00640b50)
    v = r.u16(); chk(v == 0, f'army ver {v}')
    slots = []
    for _ in range(7):
        t = r.u8()
        if t == 0xff: slots.append(None)
        elif t == 0: slots.append(creature_stack(r))
        elif t == 1: raise ScriptError('hero in script army (FUN_00728470) not supported')
        else: raise ScriptError(f'army slot type {t}')
    return slots

def seq_payload(r, ver):     # FUN_00833be0: u16 n; n x action
    return [read_node(r, ver) for _ in range(r.u16())]

# ---- action classes (54, names FUN_0081bb00, factories -> DAT_00a8d8c8) --------
B = lambda lim, what='byte': (lambda r, v: _b(r, lim, what))
U8 = lambda r, v: r.u8()
H = lambda r, v: r.u16()
I = lambda r, v: _i32(r)
S = lambda r, v: _s(r)
P = player
HS = lambda r, v: hero_sel(r)
A = lambda r, v: read_node(r, v)
N = lambda r, v: read_num(r, v)
Q = lambda r, v: read_bool(r, v)
def S_nonempty(r, v):
    s = _s(r); chk(len(s) > 0, 'empty name'); return s
def ARTS(r, v): return [artifact(r) for _ in range(r.u16())]
def RES7(r, v): return [_i32(r) for _ in range(7)]
def ARMY(r, v): return army(r)
def TEXTSEQ(r, v): return seq_payload(r, v) if v >= 1 else []
def SEQ(r, v): return seq_payload(r, v)
def CREATURE(r, v):
    c = r.u16(); chk(c < 74, f'creature {c}'); return c
def SPELL(r, v):
    s = r.u16(); chk(s < 188, f'spell {s}'); return s
def HAS_ART(r, v):            # FUN_0082c660
    f = r.u8()
    who = player(r, v) if f else _b(r, 4, 'has_artifact sel')
    return (f, who, artifact(r))

ACTIONS = {  # name: (reader fn addr, [fields])
 'build': (0x8239e0, [B(43, 'building')]),
 'change_owner': (0x823bd0, [B(7, 'owner')]),
 'clear_lc_text': (0x830140, [P]), 'clear_l_msg': (0x830140, [P]),
 'clear_vc_text': (0x830140, [P]), 'clear_v_msg': (0x830140, [P]),
 'combat': (0x824140, [B(3, 'combat sel'), ARMY, A, A]),
 'if': (0x8248d0, [Q, A, A]),
 'dec_mana': (0x81d7b0, [HS, H]), 'inc_mana': (0x81d7b0, [HS, H]),
 **{n: (0x81dac0, [HS, H, U8]) for n in ('dec_damage', 'dec_max_hp', 'dec_max_mana', 'dec_speed',
                                        'inc_damage', 'inc_max_hp', 'inc_max_mana', 'inc_speed')},
 **{n: (0x81ed00, [B(4, 'sel'), U8]) for n in ('dec_luck', 'dec_morale', 'inc_luck', 'inc_morale')},
 'dec_pop': (0x81f720, [B(9, 'sel'), H]), 'inc_pop': (0x81f720, [B(9, 'sel'), H]),
 'detonate': (0x826690, [S]), 'gosub': (0x826690, [S]),
 'disable_vc': (0x830140, [P]), 'enable_vc': (0x830140, [P]),
 'text': (0x826990, [S, TEXTSEQ]),
 'give_artifact': (0x821840, [B(4, 'sel'), ARTS]), 'rem_artifact': (0x821840, [B(4, 'sel'), ARTS]),
 'give_creature': (0x824ed0, [B(3, 'sel'), CREATURE, H]), 'take_creature': (0x824ed0, [B(3, 'sel'), CREATURE, H]),
 'give_material': (0x82fdf0, [P, RES7]), 'take_material': (0x82fd20, [P, RES7]),
 'give_skill': (0x82af60, [HS, B(36, 'skill'), B(5, 'level')]),
 'give_spell': (0x82bda0, [HS, SPELL]),
 'inc_move': (0x82d330, [B(3, 'sel'), U8]),
 'inc_exp': (0x82eae0, [HS, I]),
 'inc_level': (0x82bd00, [HS, U8]),
 'inc_skill': (0x82b230, [HS, U8, B(36, 'skill')]),
 'no_op': (0x410c50, []), 'rem_event': (0x410c50, []), 'rem_this': (0x410c50, []),
 'lose': (0x830140, [P]), 'win': (0x830140, [P]),
 'ask': (0x832280, [S, A, A]),
 'seq': (0x833be0, [SEQ]),
 'set_bool': (0x835cf0, [S, Q]), 'set_num': (0x835910, [S, N]),
 'set_lc_text': (0x834760, [P, S]), 'set_l_msg': (0x834760, [P, S]),
 'set_vc_text': (0x834760, [P, S]), 'set_v_msg': (0x834760, [P, S]),
}
NUMS = {  # 21, names FUN_00828000, factories -> DAT_00ad4260
 'creatures': (0x825e50, [B(3, 'sel'), CREATURE]),
 **{n: (0x7efef0, []) for n in ('day', 'dow', 'month', 'week', 'wom')},
 **{n: (0x820410, [N, N]) for n in ('+', '-', '*', '/', '%')},
 'exp_level': (0x82cf80, [HS]),
 'mastery': (0x82cc00, [HS, B(36, 'skill')]),
 'lit': (0x830650, [I]),
 'materials': (0x831250, [P, B(7, 'resource')]),
 'neg': (0x81ff40, [N]),
 'player': (0x830140, [P]),
 'rand': (0x832780, [I, I]),
 'total_creatures': (0x825b20, [B(3, 'sel')]), 'total_heroes': (0x825b20, [B(3, 'sel')]),
 'var': (0x837540, [S]),
}
BOOLS = {  # 24, names FUN_008286b0, factories -> DAT_00ad4200
 'and': (0x82f570, [Q, Q]), 'or': (0x82f570, [Q, Q]), 'not': (0x82f0a0, [Q]),
 'has_alignment': (0x821080, [B(3, 'sel'), B(6, 'alignment')]),
 'has_hero': (0x821280, [B(3, 'sel'), S]),
 'give_skill?': (0x82af60, [HS, B(36, 'skill'), B(5, 'level')]),
 **{n: (0x832e90, [N, N]) for n in ('==', '>', '>=', '<', '<=')},
 'false': (0x7efef0, []), 'true': (0x7efef0, []),
 'has_artifact': (0x82c660, [HAS_ART]),
 'is_dead': (0x836470, [S_nonempty]), 'is_imprisoned': (0x836470, [S_nonempty]),
 'is_alignment': (0x830fd0, [P, B(6, 'alignment')]),
 'is_color': (0x831250, [P, B(7, 'colour')]),
 'is_computer': (0x830140, [P]), 'is_eliminated': (0x830140, [P]), 'is_human': (0x830140, [P]),
 'owns_hero': (0x834760, [P, S]), 'owns_town': (0x834760, [P, S]),
 'var': (0x837540, [S]),
}

def _read(table, kind, r, ver):
    name = _s(r)
    e = table.get(name)
    chk(e is not None, f'unknown {kind} node {name!r}')
    return (name,) + tuple(f(r, ver) for f in e[1])

def read_node(r, ver): return _read(ACTIONS, 'action', r, ver)
def read_num(r, ver): return _read(NUMS, 'numeric', r, ver)
def read_bool(r, ver): return _read(BOOLS, 'boolean', r, ver)

def read_script(r):          # FUN_00827ef0 -> FUN_00410930: u16 scriptVer; action
    ver = r.u16(); return (ver, read_node(r, ver))

# ---- containers -------------------------------------------------------------
def Y(r):                    # FUN_00705e20: script; S; 7 x u32
    sc = read_script(r); s = _s(r); return (sc, s, [r.u32() for _ in range(7)])
def read_event_obj(r):       # FUN_007d3530: u16 ver==0; Y; S; u8 players(7 bits); u8 mask(2 bits)
    v = r.u16(); chk(v == 0, f'event obj ver {v}')
    y = Y(r); s = _s(r); return (y, s, r.u8(), r.u8())

def read_header_cine(r):     # FUN_00816970 (header ver>=24, called after each u8 flag in FUN_0077a420)
    v = r.u16(); chk(v == 0, f'header cine ver {v}')
    return (_s(r), _s(r), _s(r))   # text, movie name (FUN_00816b70), 2nd name (FUN_00816cd0)

def walk(n):
    """yield every node tuple in a tree"""
    if isinstance(n, tuple) and n and isinstance(n[0], str):
        yield n
    if isinstance(n, (tuple, list)):
        for x in (n[1:] if isinstance(n, tuple) and n and isinstance(n[0], str) else n):
            if isinstance(x, (tuple, list)): yield from walk(x)
