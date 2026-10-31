import sys,os,io,contextlib,re
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import probe, dev_q2 as q
CANDS=['','B','BB','BBB','BH','BHB','BHH','BI','BBI','BR','I','H','HH','S','BS','N','BN','NN','BBN','BHN','SN','BBH','BII','IB','BIB']
fns={57:q.quest_gate,58:q.quest_guard,77:q.seers_hut}
def score():
    tot=[0,0,0]; unk={}
    for c,f in fns.items():
        out=io.StringIO()
        with contextlib.redirect_stdout(out): ok,bad,exc=probe.probe(c,f,show=1000)
        tot[0]+=ok;tot[1]+=bad;tot[2]+=exc
        for m in re.findall(r"unknown node '([a-z_]+)'",out.getvalue()): unk[m]=unk.get(m,0)+1
    return tot,unk
for it in range(15):
    t,unk=score(); print(t,unk,flush=True)
    if not unk: break
    name=max(unk,key=unk.get); best=None
    for c in CANDS:
        q.SPEC[name]=c; t2,_=score()
        if best is None or t2[0]>best[0][0]: best=(t2,c)
    q.SPEC[name]=best[1]; print('  ->',name,repr(best[1]),best[0],flush=True)
