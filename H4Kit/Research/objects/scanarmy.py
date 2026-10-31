import sys,struct,collections
sys.path.insert(0,'.')
from probe import *
cnt=collections.Counter(); shown=0
for p,b,ver in bodies():
    pos=0
    while True:
        pos=b.find(b'\x00',pos)
        if pos<0:break
        o=pos-12;pos+=1
        if o<0:continue
        rec=record_at(b,o)
        if rec and rec[0]=='army':
            if b[o+13:o+15]!=b'\x00\x00' and b[o+13]<=9 and b[o+14]==0:
                cnt[b[o+13]]+=1
                if shown<12 and b[o+13]>=6: shown+=1; print(p[len(MAPS):],o,b[o:o+60].hex(' '))
print(cnt)
