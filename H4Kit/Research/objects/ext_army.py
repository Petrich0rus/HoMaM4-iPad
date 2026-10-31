"""Army / creature stack / hero readers (heroes4.exe). See SPEC_army.md."""
import os, importlib.util
_D = os.path.dirname(os.path.abspath(__file__))
def _load(n):
    p = os.path.join(_D, n)
    if not os.path.exists(p): return None
    sp = importlib.util.spec_from_file_location('_army_' + n[:-3], p); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
# script-object records (FUN_007d2fd0 / 7d3290 / 7d3530 / 7d37f0) are owned by the ownables/scripts topics
_own = _load('ext_ownables.py') or _load('dev_ownables.py')
rec_2fd0, rec_3290, rec_3530, rec_37f0 = _own.rec_2fd0, _own.rec_3290, _own.rec_3530, _own.rec_37f0
def lst(r, f):
    for _ in range(r.u16()): f(r)
def s8(r):
    v = r.u8(); return v - 256 if v >= 128 else v
def s16(r):
    v = r.u16(); return v - 65536 if v >= 32768 else v

def artifact(r):                 # FUN_00664640
    a = r.u16(); assert a <= 0xf8, ('artifact', a)
    if a in (0x7c, 0xa6):        # spell scroll / parchment: spell id
        s = r.u16(); assert s <= 0xbc, ('spell', s)
def artifact_list(r):            # FUN_00653760: u16 n; n x artifact
    for _ in range(r.u16()): artifact(r)
def spell_bitset(r):             # FUN_00865be0 -> 865990: u8 ver; ver==0: 23 bytes else 24 bytes
    v = r.u8(); r.p += 0x17 if v == 0 else 0x18

def creature_stack(r):           # t_creature_stack vt 0x98469c, vt+0xd4 = FUN_0063e0f0
    v = r.u16(); assert v <= 1, ('stack ver', v)
    t = s16(r); assert t == -1 or 0 <= t < 0x4a, ('creature', t)
    r.u16()                      # count (0 => default count computed from creature)
    if v >= 1: artifact_list(r)

def hero(r):                     # t_hero vt 0x989310, vt+0xd4 = FUN_0072f4e0
    v = r.u16(); assert 8 <= v <= 10, ('hero ver', v)
    s16(r)                       # portrait/biography id (-1 .. FUN_0073bb20())
    s8(r)                        # class -> FUN_00729750
    g = s8(r); assert g in (-1, 0, 1), ('gender', g)
    if v >= 5: s8(r)             # +0x6a0
    if v >= 5:
        if v >= 10: r.u8(); r.u8()
        else: r.u16(); r.u16()
        r.u8(); r.u8()           # 4 primary stat bonuses
    r.str16(); r.str16()         # biography (+0x5b4), name (+0x6a8)
    if v >= 3 and r.u8():
        for _ in range(36):
            k = s8(r); assert -1 <= k < 5, ('skill', k)
    if v >= 4: spell_bitset(r)
    if v >= 2:                   # FUN_0072f940: 14 equipment slots
        for _ in range(14):
            if r.u8(): artifact(r)
    if v >= 1: artifact_list(r)  # backpack
    for _ in range(3): rec_2fd0(r)          # FUN_00738700
    lst(r, rec_3290); lst(r, rec_3530); lst(r, rec_37f0)   # 738830 / 738850 / 738870
    if v >= 9: r.u8()

def army_slot(r):                # FUN_00640b50
    k = s8(r)
    if k == -1: return None      # empty stack (vt 0x9849a4, reader 428da0 reads nothing)
    if k == 0: return creature_stack(r)
    if k == 1: return hero(r)
    raise AssertionError(('slot kind', k))
def army_stacks(r):              # FUN_00640d00 (shared creature-array reader: garrisons, towns, dwellings...)
    v = r.u16(); assert v == 0, ('army ver', v)
    for _ in range(7): army_slot(r)
def army_stacks_old(r):          # FUN_00640e90 (army record ver < 3 with flag): u16 0 + one slot
    v = r.u16(); assert v == 0
    army_slot(r)

def army_record(r, ver):         # t_army vt+0x90 = FUN_00523a30 (object list flag != 0)
    v = r.u16(); assert v <= 9, ('t_army ver', v)
    if v == 0: return
    if v >= 2:
        o = r.u8(); assert o < 7, ('owner', o)
    if v >= 3: army_stacks(r)
    else:
        if r.u8(): army_stacks_old(r)
        else: army_stacks(r)
    if v >= 4:
        f = 1
        if v >= 5: f = r.u8()
        if f: r.u8(); r.u8()
    if v >= 6:
        for _ in range(3): rec_2fd0(r)       # FUN_00525fe0
        lst(r, rec_3290); lst(r, rec_3530); lst(r, rec_37f0)  # 527240 / 5274a0 / 527700
    if v >= 7:
        a = s8(r); assert -1 <= a < 6, ('ai', a)
    if v >= 8: r.u8()
    if v >= 9: r.u8()


def script_block(r):             # FUN_00525f70 / 00738700..738870 pattern: 3 x 7d2fd0, lists 7d3290, 7d3530, 7d37f0
    for _ in range(3): rec_2fd0(r)
    lst(r, rec_3290); lst(r, rec_3530); lst(r, rec_37f0)
def placement_spec(r):           # FUN_0075cae0 (shared with ownables spec_75cae0)
    assert r.u16() == 0
    k = r.str16()
    if k == 'player': r.u8()
    elif k == 'town': r.str16()

def random_monster(r, ver):      # classes 64/66, reader FUN_007f3710
    v = r.u16(); assert v <= 4, ('rmon ver', v)
    if v >= 3 and r.u8(): s8(r); s8(r)
    if v >= 2: script_block(r)
    if v >= 1: placement_spec(r)
    if v >= 4:
        a = struct.unpack('<i', bytes(r.b[r.p:r.p+4]))[0]; r.p += 4
        b = struct.unpack('<i', bytes(r.b[r.p:r.p+4]))[0]; r.p += 4
        assert a >= 0 and b >= a and (a > 0) == (b > 0), ('rmon range', a, b)

def carryover_hero(r, ver):      # class 13, reader FUN_005bf4a0
    v = r.u16(); assert v <= 2, ('carryover ver', v)
    if v >= 1:
        o = r.u8(); assert o < 7; r.str16()
    if v >= 2:
        if r.u8(): s8(r); s8(r)
        script_block(r)

def prison(r, ver):              # class 56, reader FUN_00467f20
    v = r.u16(); assert v <= 1, ('prison ver', v)
    if v == 1: hero(r)

import struct
READERS = {'army_hero': hero, 'army_stacks': army_stacks, 'army': army_record, 64: random_monster, 66: random_monster, 13: carryover_hero, 56: prison}
