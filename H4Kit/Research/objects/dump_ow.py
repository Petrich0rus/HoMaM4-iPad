import sys,collections
import os;sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from probe import bodies,record_at
cid=int(sys.argv[1]); N=int(sys.argv[2]) if len(sys.argv)>2 else 8; L=int(sys.argv[3]) if len(sys.argv)>3 else 120
k=0
for p,b,ver in bodies():
    pos=0
    while True:
        pos=b.find(b'\x00',pos)
        if pos<0: break
        o=pos-12; pos+=1
        if o<0: continue
        rec=record_at(b,o)
        if rec and rec[0]=='named' and rec[1]==cid:
            print(ver,p.split('/')[-1][:20],rec[3],b[rec[3]:rec[3]+L].hex(' ')); k+=1
            if k>=N: sys.exit()
