import sys,struct,os,re,gzip,collections
sys.path.insert(0,'.')
exec(open('cls.py').read().split("res=collections")[0])  # parse()
CLS={}
for f in os.listdir('advobj/adv_object'):
    try: ver,ot,cl=parse(open('advobj/adv_object/'+f,'rb').read())
    except Exception: continue
    nm=f[:-4] if f.endswith('.h4d') else f
    CLS[nm.lower()]=(cl[0][1],cl[1][0],cl[2][1],cl[1][1]) if cl else None
exec(open('readers.py').read().split("cache={}")[0].split("names={")[1].join(["names={",""]) if False else "")
names={}
for l in open('classlist_full.txt'):
    i,n=l.split(); names[n]=int(i)
READ_VER_ONLY=None
class R:
    def __init__(s,b,p): s.b=b;s.p=p
    def u8(s): v=s.b[s.p]; s.p+=1; return v
    def u16(s): v=struct.unpack_from('<H',s.b,s.p)[0]; s.p+=2; return v
    def u32(s): v=struct.unpack_from('<I',s.b,s.p)[0]; s.p+=4; return v
    def str16(s): n=s.u16(); v=s.b[s.p:s.p+n].decode('latin1'); s.p+=n; return v
BODY={}
MISMATCH=[]
# Plug-in readers: every ext_*.py next to this file may define READERS = {key: fn(r, ver)}
# key = class id (int), (class id, subclass name lower) for subclass-specific readers, 'army' or 'spell_artifact'.
import glob as _g, importlib.util as _iu
EXT={}
for _f in sorted(_g.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)),'ext_*.py'))):
    try:
        _sp=_iu.spec_from_file_location(os.path.basename(_f)[:-3],_f); _m=_iu.module_from_spec(_sp); _sp.loader.exec_module(_m)
        EXT.update(getattr(_m,'READERS',{}))
    except Exception as _e:
        print('# ext load failed', _f, repr(_e)[:80], file=sys.stderr)
def ver_only(r,c):
    v=r.u16(); assert v==0,('ver',v)
def gw(r,c):
    v=r.u16(); assert v in(0,1); 
    if v==1: r.str16()
def obmark(r,c):
    v=r.u16(); assert v in (0,1)
    if v: r.u16()
def outpost(r,c):
    v=r.u16(); assert v in(0,1)
    if v==1: o=r.u8(); assert o<7

SUBCLASS_USED={4,31,40,76,98}
VERONLY={36,75,2,3,4,5,6,7,8,9,11,12,14,15,16,17,19,20,22,24,27,28,30,31,34,35,37,39,40,41,42,43,45,46,47,51,53,54,55,59,60,63,65,68,71,74,80,84,88,89,92,94,96,97,98,99,100,10,1,26,78,79,85,93,101,87}
VERSTR={49,83}
OWNSCRIPT={38,81,103}
GW={23,25,29,33,52,86,90,91,104}
def read_triple(r):
    assert r.u16()==0
    a=r.u16(); n1=r.str16(); b=r.u16(); n2=r.str16(); c=r.u16(); n3=r.str16()
    return (a,n1,b,n2,c,n3)
def find_start(body):
    keys=set(CLS)
    best=None
    for o in range(0,len(body)-20):
        if body[o+12]!=0: continue
        x,y,z=struct.unpack_from('<III',body,o)
        if x>300 or y>300 or z>1: continue
        L=struct.unpack_from('<H',body,o+13)[0]
        if not(3<=L<=100): continue
        s=body[o+15:o+15+L]
        try: s=s.decode('latin1').lower()
        except: continue
        if s in keys: return o
    return None
def walk(body,o,ver=27,maxn=100000,verbose=False):
    r=R(body,o); seq=[]
    n=struct.unpack_from('<I',body,o-4)[0]
    for k in range(n):
        st=r.p
        try:
            x=r.u32();y=r.u32();z=r.u32();fl=r.u8()
            if fl:
                if 'army' in EXT: EXT['army'](r,ver); seq.append((st,'ARMY',x,y,z)); continue
                seq.append((st,'ARMY',x,y,z)); return seq,n,st,'army reader missing'
            name=r.str16(); tri=read_triple(r)
            ci=CLS.get(name.lower())
            cname=ci[0] if ci else None
            cid=names.get(cname,-1)
            if cname is None: return seq,n,st,'unknown model '+name
            if (tri[1].lower(),tri[3].lower(),tri[5].lower())!=(ci[0].lower(),ci[3].lower(),ci[2].lower()):
                MISMATCH.append((name,tri,ci))
            sub=ci[3].lower()
            if (cid,sub) in EXT: EXT[(cid,sub)](r,ver); seq.append((st,name,cname,cid,x,y,z,tri)); continue
            if cid in EXT: EXT[cid](r,ver); seq.append((st,name,cname,cid,x,y,z,tri)); continue
            if cid==4 and sub in ('parchment','scroll') and 'spell_artifact' in EXT:
                EXT['spell_artifact'](r,ver); seq.append((st,name,cname,cid,x,y,z,tri)); continue
            if cid==4 and ci[3].lower() in ('parchment','scroll'):
                seq.append((st,name,cname,cid,x,y,z,tri)); return seq,n,st,'reader missing for class 4 spell_artifact'
            if cid in VERONLY: ver_only(r,cid)
            elif cid in GW: gw(r,cid)
            elif cid in VERSTR: gw(r,cid)
            elif cid in OWNSCRIPT:
                v=r.u16(); assert v<=2,('ownscript ver',v)
                if v>=1: o=r.u8(); assert o<7
                if v>=2:
                    nn=r.u16(); assert nn==0,('events',nn)
            elif cid==48: obmark(r,cid)
            elif cid==50: outpost(r,cid)
            else:
                seq.append((st,name,cname,cid,x,y,z,tri)); return seq,n,st,'reader missing for class %d %s'%(cid,cname)
            seq.append((st,name,cname,cid,x,y,z,tri))
        except AssertionError as e:
            return seq,n,st,'assert %s'%(e,)
    return seq,n,r.p,'complete'
if __name__=='__main__':
    p=sys.argv[1]
    raw=open(p,'rb').read(); body=gzip.decompress(raw[15:])
    o=find_start(body)
    print('start',o)
    seq,n,at,why=walk(body,o)
    print('count',n,'parsed',len(seq),'stopped at',at,why)
    print(collections.Counter(s[2] for s in seq if s[1]!='ARMY').most_common(8))
    if seq: print(seq[-1])
