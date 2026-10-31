import gzip, struct, glob, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scripts
MAPS="/Volumes/Heroes of might and magic IV/Heroes IV.app/Contents/SharedSupport/prefix/drive_c/GOG Games/HoMM 4 Complete/maps/"
class R:
    def __init__(s,d,o=0): s.d=d; s.o=o
    def u8(s): v=s.d[s.o]; s.o+=1; return v
    def u16(s): v=struct.unpack_from('<H',s.d,s.o)[0]; s.o+=2; return v
    def u32(s): v=struct.unpack_from('<I',s.d,s.o)[0]; s.o+=4; return v
    def raw(s,n):
        if s.o+n>len(s.d): raise EOFError
        v=s.d[s.o:s.o+n]; s.o+=n; return v
    def str(s): n=s.u16(); return s.raw(n).decode('cp1252')
def load(path):
    f=open(path,'rb').read()
    assert f[:10]==b'H4CAMPAIGN'
    d=gzip.decompress(f[15:])
    return d
def header(d):
    r=R(d); ver=r.u16()
    if ver>=28: r.u16()
    size=r.u16(); lv=r.u8(); r.u32(); pc=r.u8()
    for _ in range(pc): r.raw(5)
    name=r.str(); r.u8(); r.str(); assert r.u16()==0
    tc=r.u8(); r.raw(tc)
    if r.u8(): r.str()
    if r.u8(): r.str()
    if ver>=25: r.u8()
    if ver>=24:
        for _ in range(2):           # FUN_0077a420 -> FUN_00816970 (victory / defeat cinematic)
            if r.u8(): scripts.read_header_cine(r)
    if ver>=27: r.str()
    if ver>=29: r.u8()
    return ver,size,lv,pc,name,r.o
if __name__=='__main__':
    for p in sorted(glob.glob(MAPS+'**/*.h4c',recursive=True))[:3]:
        d=load(p); h=header(d); print(p.split('/')[-1],h[:5],h[5],len(d)); print(d[h[5]:h[5]+160].hex(' '))
