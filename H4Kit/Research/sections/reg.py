import sys,re;sys.path.insert(0,'/private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad/objects');import pe
from names import L, names
IDX={}
for k,l in enumerate(L):
    m=re.match(r'\s*([0-9a-f]{6}):',l)
    if m: IDX[int(m.group(1),16)]=k
def fn(a,maxn=400):
    i=IDX[a]; out=[]; mx=0
    for l in L[i:i+maxn]:
        m=re.match(r'\s*([0-9a-f]{6}):\s*(.*)',l)
        if not m: continue
        ins=re.sub(r'\s*<[^>]*>','',re.sub(r'\s*#.*','',m.group(2))).strip().replace('\t',' ')
        ad=int(m.group(1),16); out.append((ad,ins))
        mj=re.match(r'j\w+ 0x([0-9a-f]+)$',ins)
        if mj: mx=max(mx,int(mj.group(1),16))
        if ins.startswith('ret') and ad>=mx: break
    return out
def regs():
    R=[]
    for tgt,tab in ((0x4111f0,'act'),(0x411290,'num'),(0x411330,'bool')):
        for k,l in enumerate(L):
            if 'calll\t0x%x '%tgt in l:
                ctx=L[k-6:k+4]; idx=vt=None
                for c in ctx:
                    m=re.search(r'pushl\s+\$0x([0-9a-f]+)$',c.split('#')[0].strip()) 
                    if m: idx=int(m.group(1),16)
                    m=re.search(r'movl\s+\$0x(9[0-9a-f]{5}), \(%e..\)',c)
                    if m: vt=int(m.group(1),16)
                R.append((tab,idx,vt))
    return R
if __name__=='__main__':
    for r in regs(): print(r[0],r[1],hex(r[2] or 0))
NM={'act':names(0x81bb00),'num':names(0x828000),'bool':names(0x8286b0)}
SLOT={'act':0x10,'num':0x24,'bool':0x24}
def nodevt(fvt):
    f=pe.u32(fvt); vts=[]
    for a,i in fn(f):
        m=re.search(r'movl \$0x(9[0-9a-f]{5}), \(%e..\)',i)
        if m: vts.append(int(m.group(1),16))
        m=re.match(r'calll 0x([0-9a-f]+)$',i)
        if m and int(m.group(1),16)!=0x8d98a0:
            vts.append(('call',int(m.group(1),16)))
    return f,vts
def table():
    T=[]
    for tab,idx,fvt in regs():
        f,vts=nodevt(fvt)
        nv=[v for v in vts if isinstance(v,int)]
        vt=nv[-1] if nv else None
        rd=pe.u32(vt+SLOT[tab]) if vt else None
        T.append((tab,idx,NM[tab].get(idx),fvt,f,vt,rd,vts))
    return T
if __name__=='__main__' and 'tab' in sys.argv:
    for t in sorted(table(),key=lambda t:(t[0],t[1])):
        print(t[0],t[1],t[2],'fvt=%x create=%x nodevt=%s read=%s'%(t[3],t[4],hex(t[5]) if t[5] else None,hex(t[6]) if t[6] else None),[hex(v) if isinstance(v,int) else (v[0],hex(v[1])) for v in t[7]])
