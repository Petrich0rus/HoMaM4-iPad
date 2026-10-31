import sys; sys.path.insert(0,".")
import re,pickle
src=open('readers.py').read().split("cache={}")[0]
exec(src)
def primary(ctor):
    f=func(ctor,3000)
    thisreg=None
    for l in f[:25]:
        m=re.search(r'movl\t%ecx, (%\w+)\s*$',l)
        if m: thisreg=m.group(1); break
    stores=[]
    for l in f:
        for reg in ([thisreg] if thisreg else []):
            m=re.search(r'movl\t\$0x([0-9a-f]+), \(%s\)'%reg,l)
            if m:
                v=int(m.group(1),16)
                if 0x970000<=v<0xa46000 and rtti(v): stores.append(v)
    return thisreg,stores
out={}
for cls,sub,reg,vt,s0 in rows:
    c=ctor_of(s0)
    if c is None: out[(cls,sub)]=None; continue
    tr,st=primary(c)
    if st:
        v=st[-1]; out[(cls,sub)]=(c,v,rtti(v)[4:-2],u32(v+0x90),[hex(x) for x in st])
    else: out[(cls,sub)]=(c,None,tr,None,[])
pickle.dump(out,open('primary.pkl','wb'))
for k,v in out.items():
    if v is None: print(k,names[k[0]],'NOCTOR')
    else: print(k,names[k[0]],hex(v[0]),hex(v[1]) if v[1] else None,v[2],hex(v[3]) if v[3] else None,v[4])
