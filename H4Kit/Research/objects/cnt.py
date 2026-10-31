import sys,os;sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import probe,importlib.util,collections
sp=importlib.util.spec_from_file_location('dev_ownables','dev_ownables.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
C=collections.Counter(); orig=m.lst
def lst(r,f):
    p=r.p; n=r.r16() if 0 else None
    import struct; n=struct.unpack_from('<H',r.b,r.p)[0]; C[(CID,f.__name__,n>0)]+=1; orig(r,f)
m.lst=lst
for CID,fn in [(38,m.owned_scriptable),(81,m.owned_scriptable),(103,m.owned_scriptable),(21,m.owned_scriptable),(102,m.owned_scriptable),(61,m.random_dwelling),(0,m.abandoned_mine),(44,m.mine_garrison),(32,m.mine_garrison)]:
    probe.probe(CID,fn,show=0)
for k,v in sorted(C.items()): print(k,v)
