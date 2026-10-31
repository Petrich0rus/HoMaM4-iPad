# Reference for slice 5a: sections (parse_sections) + object walk (chain) over maps/**/*.h4c
import sys, os, glob, collections
S = os.path.dirname(os.path.abspath(__file__))
os.chdir(S + '/sections'); sys.path.insert(0, S + '/sections')
import parse_sections as ps
from hdr import load, header
os.chdir(S + '/objects'); sys.path.insert(0, S + '/objects')
import chain
MAPS = "/Volumes/Heroes of might and magic IV/Heroes IV.app/Contents/SharedSupport/prefix/drive_c/GOG Games/HoMM 4 Complete/maps/"
paths = sorted(glob.glob(MAPS + '**/*.h4c', recursive=True))
print('# population', len(paths))
for p in paths:
    rel = p[len(MAPS):]
    try:
        d = load(p); ver, size, lv, pc, name, bo = header(d)
    except Exception as e:
        print(f'{rel}\tHEADER-FAIL\t{e!r}'); continue
    try:
        end = ps.parse_body(d, ver, pc, bo, {})
    except Exception as e:
        print(f'{rel}\tSECTIONS-FAIL\t{e!r}'); continue
    body = d[bo:]                          # body-relative offsets, like H4Scenario.body
    o = end - bo + 4
    n0 = len(chain.MISMATCH)
    seq, n, at, why = chain.walk(body, o, ver)
    spell = sum(1 for s in seq if len(s) > 2 and why.endswith('spell_artifact') and s is seq[-1])
    decoded = len(seq) - (0 if why == 'complete' else 1)
    print(f'{rel}\tobjstart={end-bo}\tcount={n}\tdecoded={decoded}\tstop={at}\t{why}\tmismatch={len(chain.MISMATCH)-n0}')
