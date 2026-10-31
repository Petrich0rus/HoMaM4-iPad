import sys,collections
import os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from probe import bodies, record_at, MAPS
want=int(sys.argv[1]); n=int(sys.argv[2]) if len(sys.argv)>2 else 5
cnt=collections.Counter(); shown=0
for p,b,ver in bodies():
    pos=0
    while True:
        pos=b.find(b'\x00',pos)
        if pos<0: break
        o=pos-12; pos+=1
        if o<0: continue
        rec=record_at(b,o)
        if rec and rec[0]=='named' and rec[1]==want:
            cnt[rec[2]]+=1
            if shown<n: shown+=1; print(p[len(MAPS):],ver,rec[2],b[rec[3]:rec[3]+160].hex(' '))
print(cnt)
