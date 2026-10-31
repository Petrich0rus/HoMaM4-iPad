import sys; sys.path.insert(0,".")
import re
from pe import *
L=open('text.asm').read().split('\n')
start=[i for i,l in enumerate(L) if l.strip().startswith('4635d0:')][0]
out=[]; cur=None
for l in L[start:start+60000]:
    if re.search(r'\tretl',l) and 'movl' not in l and len(out)>5 and cur is None: pass
    m=re.search(r'pushl\t\$0x([0-9a-f]+)',l)
    if m:
        v=int(m.group(1),16)
        if 0xa46000<=v<0xad6000:
            try:
                s=cstr(v)
                if re.fullmatch(r'[a-z_0-9]+',s): cur=s
            except: pass
    m=re.search(r'movl\t\$(-?0x[0-9a-f]+|\d+), 0x(a8f[0-9a-f]+)',l)
    if m and cur:
        out.append((cur,m.group(1),m.group(2))); cur=None
    if l.strip().startswith('463') is False and 'retl' in l and len(out)>100: break
for o in out: print(o)
print(len(out))
