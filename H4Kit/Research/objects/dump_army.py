import sys,os;sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import probe, importlib.util
sp=importlib.util.spec_from_file_location('m','dev_ownables.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
cid=int(sys.argv[1]);N=int(sys.argv[2])
def army(r):
    print(r.b[r.p:r.p+90].hex(' ')); raise AssertionError('x')
m.army=army
probe.probe(cid,m.mine,show=0) if N else None
