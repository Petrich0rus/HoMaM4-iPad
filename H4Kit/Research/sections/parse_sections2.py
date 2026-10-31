import sys, glob, collections
sys.path.insert(0, '.')
from hdr2 import R, load, header, MAPS
import scripts

class Bad(Exception): pass
def chk(c, msg):
    if not c: raise Bad(msg)

def bitset(r, maxbits):       # FUN_00551980 (maxbits 248) : u16 a, u16 nbits, ceil(nbits/8) bytes
    a = r.u16(); n = r.u16(); chk(a == 0, 'bitset first u16 != 0')
    chk(n <= maxbits, f'bitset nbits {n}'); r.raw((n + 7) // 8); return a, n


def Z(r):   # FUN_00827ef0: exe-decoded grammar (scripts.py)
    try: scripts.read_script(r)
    except scripts.ScriptError as e: raise Bad(str(e) + ' @' + str(r.o))
def S(r):   # FUN_00879420
    return r.str()
def Y(r):   # FUN_00705e20
    Z(r); S(r); [r.u32() for _ in range(7)]
def X(r):   # FUN_0088c700
    Y(r); S(r); r.u16(); r.u16()
def elemA(r):  # FUN_00726af0
    chk(r.u16() == 0, 'A ver'); X(r); r.u8(); r.u8()
def elemB(r):  # FUN_00726d70
    chk(r.u16() == 0, 'B ver'); Y(r); S(r)
def elemC(r):  # FUN_00726de0
    chk(r.u16() == 0, 'C ver'); Z(r); S(r)
def elemD(r):  # FUN_00726f90
    v = r.u16(); chk(v <= 1, 'D ver'); Y(r)
    if v: r.u8(); r.u8()
    S(r)
def counted(r, f, stats, name):
    n = r.u16(); stats[name] = n
    for _ in range(n): f(r)

def parse_body(d, ver, pc, start, stats):
    r = R(d, start)
    counted(r, elemA, stats, 'A')            # 004cfa90
    counted(r, elemB, stats, 'B')            # 004cfcf0
    counted(r, elemC, stats, 'C')            # 004cff50
    if ver >= 12: counted(r, elemD, stats, 'D')   # 004d0200
    for i in range(12):                      # 007c6340
        if ver >= 13:
            chk(r.u16() == 0, 'avail ver'); flag = r.u8(); r.u16()
            if flag:
                stats['avail_flag'] = stats.get('avail_flag', 0) + 1
                for _ in range(r.u16()):          # FUN_007c7130: typename string + polymorphic payload
                    chk(r.u16() == 0, 'avail obj ver'); t = r.str()
                    if t == 'artifact': r.raw(6)
                    elif t == 'material': r.raw(5)
                    else: raise Bad('unknown avail object ' + t)
    if ver >= 16:                            # 004d0530
        for _ in range(pc):
            r.u8(); fl = r.u8()
            if fl: r.u16()
            if ver >= 23: r.u8()
    if ver >= 18:                            # 004d0750
        if r.u8(): bitset(r, 248)
    if ver >= 18:                            # 004d0920
        if r.u8(): r.raw(r.u16())
    if ver >= 18:                            # 004f0ec0 / 00857ec0
        if r.u8():
            chk(r.u8() == 0, '857ec0 first byte'); r.raw(5)
    if ver >= 18:                            # 004d0c10
        if r.u8():
            n = r.u16(); chk(n <= 188, 'c10 nbits'); r.raw((n + 7) // 8)
    if 21 <= ver < 24:                       # 004d1080 (not for 27/29)
        raise Bad('ver 21-23 unsupported')
    if ver >= 22: bitset(r, 248); bitset(r, 248)   # 005515c0 x2
    if ver >= 23:
        for lim in (248, 188, 188):          # 005480b0, 0085e790 x2
            chk(r.u16() == 0, 'idmap ver'); n = r.u16()
            for _ in range(n):
                i = r.u16(); chk(i < lim, 'idmap id'); v = r.u8(); chk(v in (1, 2), 'idmap val')
    return r.o

if __name__ == '__main__':
    ok = 0; cnts = []; fails = []
    for p in sorted(glob.glob(MAPS + '**/*.h4c', recursive=True)):
        nm = p[len(MAPS):]
        try:
            d = load(p); ver, size, lv, pc, name, bo = header(d)
        except Exception as e:
            fails.append((nm, 'header: ' + repr(e)[:80])); continue
        st = {}
        try:
            end = parse_body(d, ver, pc, bo, st)
            n = R(d, end).u32()
            plausible = 0 < n < 20000
            print(f'{"OK " if plausible else "?? "}{nm:45s} v{ver} body@{bo} objlist@{end} (rel {end-bo}) nobj={n} {st}')
            if plausible: ok += 1; cnts.append(n)
            else: fails.append((nm, f'implausible count {n}'))
        except Exception as e:
            print(f'FAIL {nm:45s} v{ver} {repr(e)[:80]} {st}'); fails.append((nm, repr(e)[:80]))
    print('success', ok, '/', len(glob.glob(MAPS + '**/*.h4c', recursive=True)))
    if cnts: print('nobj min/median/max', min(cnts), sorted(cnts)[len(cnts)//2], max(cnts))
    for f in fails: print('FAILED', f)
