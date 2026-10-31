import re,sys
L=open('/private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad/objects/text.asm').read().split('\n')
idx={}
for i,l in enumerate(L):
    m=re.match(r'\s*([0-9a-f]{6}):',l)
    if m: idx[int(m.group(1),16)]=i
def fn(a):
    i=idx[a]; out=[]; mx=a; 
    for j in range(i,i+3000):
        m=re.match(r'\s*([0-9a-f]{6}):\s*(.*)',L[j])
        if not m: continue
        ad=int(m.group(1),16)
        ins=re.sub(r'\s*#.*','',m.group(2)).strip().replace('\t',' ')
        ins=re.sub(r'<[^>]*>','',ins)
        if ins=='nop' and ad>mx and out and out[-1][1].startswith('ret'): break
        out.append((ad,ins))
        mj=re.match(r'j\w+ 0x([0-9a-f]+)',ins)
        if mj: mx=max(mx,int(mj.group(1),16))
        if ins.startswith('ret') and ad>=mx: break
    return out
def show(a,filt=True):
    print('==',hex(a))
    for ad,ins in fn(a):
        print('%x %s'%(ad,ins))
if __name__=='__main__':
    for a in sys.argv[1:]: show(int(a,16))
