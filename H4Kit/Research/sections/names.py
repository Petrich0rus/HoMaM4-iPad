import sys,re;sys.path.insert(0,'/private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad/objects');import pe
L=open('/private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad/objects/text.asm').read().split('\n')
def lines(a):
    i=[k for k,l in enumerate(L) if l.startswith('  %x:'%a)][0]
    out=[]
    for l in L[i:i+3000]:
        out.append(l)
        if 'retl' in l: break
    return out
def names(a):
    ecx=None;s=None;res={};base=None
    for l in lines(a):
        m=re.search(r'movl\s+\$0x([0-9a-f]+), %ecx',l)
        if m: ecx=int(m.group(1),16); base=ecx if base is None else min(base,ecx)
        m=re.search(r'pushl\s+\$0x(a[4-9][0-9a-f]{4})\b',l)
        if m: s=int(m.group(1),16)
        m=re.search(r'movl\s+\$0x(a[4-9][0-9a-f]{4}), %edi',l)
        if m: s=int(m.group(1),16)
        if ('calll\t0x401d30' in l or 'calll\t0x44c700' in l) and s:
            res[ecx]=pe.cstr(s); s=None
    b=min(res); return {(k-b)//16:v for k,v in res.items()}
if __name__=='__main__':
    for a in sys.argv[1:]:
        r=names(int(a,16)); print('==',a,len(r)); print(' '.join('%d:%s'%(k,r[k]) for k in sorted(r)))
