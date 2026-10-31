import sys,struct,collections
sys.path.insert(0,'.')
from probe import *
cnt=collections.Counter();shown=0
for p,b,ver in bodies():
    for o in range(0,len(b)-40):
        fl=b[o+12]
        if fl==0: continue
        x,y,z=struct.unpack_from('<iii',b,o)
        if not(0<=x<=255 and 0<=y<=255 and z in(0,1)): continue
        v=struct.unpack_from('<H',b,o+13)[0]
        if v!=9 or fl!=1: continue
        if b[o+15]>6: continue
        if b[o+16:o+18]!=b'\0\0': continue  # army u16 0
        k=b[o+18]
        if k not in (0,1,0xff): continue
        cnt[(ver,v,fl)]+=1
        if shown<6: shown+=1; print(p[len(MAPS):][-30:],o,ver,b[o:o+70].hex(' '))
print(cnt)
