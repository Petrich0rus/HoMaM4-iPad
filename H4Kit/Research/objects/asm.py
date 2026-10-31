import sys,re
L=open('text.asm').read().split('\n')
idx={}
for i,l in enumerate(L):
    m=re.match(r'\s*([0-9a-f]{6}):',l)
    if m: idx[int(m.group(1),16)]=i
def show(a,n=None):
    i=idx[a]; out=[]
    for j in range(i,i+4000):
        l=L[j]; m=re.match(r'\s*([0-9a-f]{6}):\s*(.*)',l)
        if not m: continue
        ins=re.sub(r'<[^>]*>','',re.sub(r'\s*#.*','',m.group(2))).strip().replace('\t',' ')
        out.append('%s %s'%(m.group(1)[2:],ins))
        if j>i+3 and re.search(r'\t(int3|nop)\s*$',l) and 'ret' in L[j-1]: break
        if n and len(out)>=n: break
    return out
for a in sys.argv[1:]:
    print('==',a); print('\n'.join(show(int(a,16))))
