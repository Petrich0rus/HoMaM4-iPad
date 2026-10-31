"""Validate one class reader in isolation over all 105 maps.
usage (from this dir):  python3 -I probe.py <class_id> [subclass_name] <module.py> <function>
       or import:       from probe import probe; probe(cid, fn, sub=None)
Finds every record of class <cid> (named records: u32 x,y,level <=1, u8 0, str16 model resolving to cid, triple),
runs fn(r, ver) on the payload, then checks that the next bytes start a valid record:
 named record of any known model (+ triple parses) or army record (x,y < 400, level<=1, flag!=0),
 or the end of the object list (declared count reached is not known here, so 'end?' is reported separately).
Prints totals: ok / fail / exceptions, with the first failures (map, offset, hex)."""
import sys, os, glob, gzip, struct, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain
from chain import R, CLS, names, read_triple
MAPS = "/Volumes/Heroes of might and magic IV/Heroes IV.app/Contents/SharedSupport/prefix/drive_c/GOG Games/HoMM 4 Complete/maps/"
PATHS = sorted(glob.glob(MAPS + '**/*.h4c', recursive=True))
_bodies = {}
def bodies():
    for p in PATHS:
        if p not in _bodies:
            raw = open(p, 'rb').read(); d = gzip.decompress(raw[15:])
            ver = struct.unpack_from('<H', d, 0)[0]
            _bodies[p] = (d, ver)
        yield p, _bodies[p][0], _bodies[p][1]
def record_at(b, o):
    """returns ('named', cid, sub, payload_offset) / ('army', payload_offset) / None"""
    if o + 13 > len(b): return None
    x, y, z = struct.unpack_from('<iii', b, o)
    if not (-64 <= x <= 400 and -64 <= y <= 400 and 0 <= z <= 1): return None
    fl = b[o + 12]
    if fl:
        return ('army', o + 13)
    r = R(b, o + 13)
    try:
        L = struct.unpack_from('<H', b, r.p)[0]
        if not 1 <= L <= 200: return None
        name = r.str16(); ci = CLS.get(name.lower())
        if not ci: return None
        tri = read_triple(r)
        if tri[1].lower() != ci[0].lower(): return None
        return ('named', names.get(ci[0], -1), ci[3].lower(), r.p)
    except Exception:
        return None
def probe(cid, fn, sub=None, show=8):
    ok = bad = exc = 0; fails = []
    for p, b, ver in bodies():
        pos = 0
        while True:
            pos = b.find(b'\x00', pos)
            if pos < 0: break
            o = pos - 12; pos += 1
            if o < 0: continue
            rec = record_at(b, o)
            if not rec or rec[0] != 'named' or rec[1] != cid or (sub and rec[2] != sub): continue
            r = R(b, rec[3])
            try:
                fn(r, ver)
            except Exception as e:
                exc += 1; fails.append((p[len(MAPS):], o, 'EXC ' + repr(e)[:60], b[rec[3]:rec[3]+40].hex(' '))); continue
            nxt = record_at(b, r.p)
            if nxt: ok += 1
            else:
                bad += 1; fails.append((p[len(MAPS):], o, 'next?', b[r.p:r.p+40].hex(' ')))
    print(f'class {cid} {sub or ""}: ok={ok} badnext={bad} exceptions={exc}')
    for f in fails[:show]: print('  ', *f)
    return ok, bad, exc
if __name__ == '__main__':
    import importlib.util
    a = sys.argv[1:]
    cid = int(a[0]); sub = None
    if len(a) == 4: sub = a[1]; a = a[1:]
    sp = importlib.util.spec_from_file_location('m', a[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
    probe(cid, getattr(m, a[2]), sub)
