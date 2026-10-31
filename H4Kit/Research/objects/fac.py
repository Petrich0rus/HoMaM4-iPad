import sys; sys.path.insert(0,".")
import re
from pe import *
rows=[]
for l in open('regs.txt'):
    p=l.split(' ',2); a,t=p[0],p[1]
    pushes=re.findall(r'pushl\t\$0x([0-9a-f]+)',p[2])
    vt=re.search(r'movl\t\$0x([0-9a-f]+), 0x([0-9a-f]+)',p[2].split('calll')[-1])
    if t=='7c7b20': cls=int(pushes[-1],16); sub=None
    else: cls=int(pushes[-1],16); sub=int(pushes[-2],16)
    vtab=int(vt.group(1),16); slot0=u32(vtab)
    rows.append((cls,sub,int(a,16),vtab,slot0))
rows=sorted(set(rows),key=lambda r:(r[0],r[1] if r[1] is not None else -1))
for r in rows: print(r[0],r[1],hex(r[2]),hex(r[3]),hex(r[4]))
import pickle; pickle.dump(rows,open('rows.pkl','wb'))
