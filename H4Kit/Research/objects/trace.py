import sys; sys.path.insert(0,".")
import re
L=open('text.asm').read().split('\n')
idx={}
for i,l in enumerate(L):
    m=re.match(r'\s*([0-9a-f]{6}):',l)
    if m: idx[int(m.group(1),16)]=i
def trace(a,maxn=3000):
    i=idx[a]; out=[]; lastpush=[]
    for j in range(i,min(i+maxn,len(L))):
        l=L[j]
        m=re.match(r'\s*([0-9a-f]{6}):\s*(.*)',l)
        if not m: continue
        ad,ins=m.groups(); ins=ins.strip()
        ins=re.sub(r'\s*#.*','',ins); ins=re.sub(r'<[^>]*>','',ins).strip()
        if ins.startswith('pushl'): lastpush.append(ins.split('\t')[-1])
        tok=None
        if re.match(r'calll\t\*0x18\(',ins):
            tok='READ(%s)'%(lastpush[-1] if len(lastpush)>=1 and False else '')
            # args: pushl len (last pushed first? order: push len, push ptr) -> len pushed first
            ps=lastpush[-2:] ; tok='READ[%s]'%(ps[0] if ps else '?')
        elif ins.startswith('calll'):
            tok='CALL '+ins.split('\t')[-1].replace('0x','')
        elif re.match(r'(cmp[lwb]|testb|testl|je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jmp|retl|js|jns)\b',ins):
            tok=ins.replace('\t',' ')
        if tok: out.append('%s:%s'%(ad[-4:],tok))
        if ins.startswith('retl') and (j-i)>15 and not re.search(r'\bj[a-z]+\t0x'+ad[-6:],''):
            # stop at last ret only if next is int3/nop padding
            nxt=L[j+1] if j+1<len(L) else ''
            if 'int3' in nxt or 'nop' in nxt: break
        if len(lastpush)>6: lastpush=lastpush[-6:]
    return out
if __name__=='__main__':
    for a in sys.argv[1:]:
        print('==',a); print(' '.join(trace(int(a,16))))
