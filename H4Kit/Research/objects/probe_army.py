"""probe for anonymous army records (flag != 0). Candidate: x,y in 0..255, level 0/1, flag 1, u16 ver 1..9,
owner<7, then u16 0 + slot kind in (-1,0,1). Only candidates preceded by the end of a valid record are not known,
so we report how many candidates parse and are followed by a valid record."""
import sys, struct, collections, importlib.util
sys.path.insert(0, '.')
from probe import bodies, record_at, MAPS
from chain import R
sp = importlib.util.spec_from_file_location('m', sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
fn = getattr(m, sys.argv[2])
ok = bad = exc = 0; fails = []; kinds = collections.Counter()
for p, b, ver in bodies():
    for o in range(len(b) - 20):
        if b[o+12] == 0: continue
        x, y, z = struct.unpack_from('<iii', b, o)
        if not (0 <= x < 256 and 0 <= y < 256 and z in (0, 1)): continue
        v = struct.unpack_from('<H', b, o+13)[0]
        if v != 9 or b[o+12] != 1 or b[o+15] > 6 or b[o+16:o+18] != b'\0\0' or b[o+18] not in (0, 1, 0xff): continue
        r = R(b, o+13)
        try: fn(r, ver)
        except Exception as e:
            exc += 1; fails.append((p[len(MAPS):][-28:], o, 'EXC '+repr(e)[:50], b[o:o+48].hex(' '))); continue
        kinds[(ver, v, b[o+12], b[o+18])] += 1
        if record_at(b, r.p): ok += 1
        else: bad += 1; fails.append((p[len(MAPS):][-28:], o, 'next?', b[r.p:r.p+40].hex(' ')))
print(f'army: ok={ok} badnext={bad} exceptions={exc}'); print(kinds)
for f in fails[:int(sys.argv[3]) if len(sys.argv)>3 else 10]: print('  ', *f)
