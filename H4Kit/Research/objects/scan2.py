import sys,struct,collections,re
sys.path.insert(0,'.')
from probe import *
c=collections.Counter();ex={}
for p,b,ver in bodies():
    for m in re.finditer(rb'(?s)[\x00-\xc8]\x00\x00\x00[\x00-\xc8]\x00\x00\x00[\x00\x01]\x00\x00\x00([\x01-\x09])([\x00-\x09])\x00',b):
        pass
    for o in range(len(b)-30):
        if b[o+12] and b[o+3]==0 and b[o+7]==0 and b[o+8+1:o+8+4]==b'\x00\x00\x00' and b[o+8]<=1 and b[o+1:o+3]==b'\x00\x00' and b[o+5:o+7]==b'\x00\x00' and b[o+12]<=3 and b[o+14]==0 and b[o+13]<=9 and b[o]<250 and b[o+4]<250 and b[o+13]>0:
            k=(b[o+12],b[o+13]);c[k]+=1; ex.setdefault(k,[]).append((p[len(MAPS):][-25:],o,b[o:o+70].hex(' ')))
print(c)
for k,v in ex.items(): print(k,v[:3])
