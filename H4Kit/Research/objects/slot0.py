import sys; sys.path.insert(0,".")
import re,pickle
from pe import *
rows=pickle.load(open('rows.pkl','rb'))
L=open('text.asm').read().split('\n')
idx={}
for i,l in enumerate(L):
    m=re.match(r'\s*([0-9a-f]{6}):',l)
    if m: idx[int(m.group(1),16)]=i
def func(a,maxn=400):
    i=idx[a]; out=[]
    for j in range(i,min(i+maxn,len(L))):
        out.append(L[j])
        if re.search(r'\tret',L[j]) : break
    return out
def rtti(vt):
    try:
        col=u32(vt-4)
        if u32(col)!=0: return None
        td=u32(col+12)
        return cstr(td+8)
    except Exception: return None
seen={}
for cls,sub,reg,vt,s0 in rows:
    if s0 in seen: r=seen[s0]
    else:
        f=func(s0)
        txt='\n'.join(f)
        sizes=re.findall(r'pushl\t\$(0x[0-9a-f]+)\s*\n[^\n]*calll\t0x8d98a0',txt)
        calls=re.findall(r'calll\t0x([0-9a-f]+)',txt)
        r=(sizes,calls,len(f)); seen[s0]=r
    print(cls,sub,hex(s0),r)
print('=====')
def ctor_of(s0):
    f=func(s0,400); txt='\n'.join(f)
    calls=[c for c in re.findall(r'calll\t0x([0-9a-f]+)',txt)]
    c=[x for x in calls if x not in ('8d98a0','411f50','4f93b0','4f9490','4120f0','404ba0')]
    return int(c[0],16) if c else None
def vts(ctor):
    f=func(ctor,2500)
    res=[]
    for l in f:
        m=re.search(r'movl\t\$0x([0-9a-f]+), (-?0x[0-9a-f]+)?\((%\w+)\)',l)
        if m:
            v=int(m.group(1),16)
            if 0x970000<=v<0xa46000:
                n=rtti(v)
                if n: res.append((m.group(2) or '0',n,hex(v)))
    return res
cache={}
for cls,sub,reg,vt,s0 in rows:
    c=ctor_of(s0)
    if c is None: print(cls,sub,hex(s0),'noctor'); continue
    if c not in cache: cache[c]=vts(c)
    print(cls,sub,'ctor',hex(c),cache[c])
