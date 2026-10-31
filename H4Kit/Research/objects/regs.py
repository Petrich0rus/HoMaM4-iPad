import re,json
L=open('text.asm').read().split('\n')
out=[]
for i,l in enumerate(L):
    m=re.search(r'calll\s+0x(7c7b20|7c7c40)\b',l)
    if m:
        ctx=[x.split('\t',1)[-1].strip() if '\t' in x else x for x in L[i-5:i+3]]
        out.append((l.split(':')[0].strip(),m.group(1),ctx))
for a,t,c in out: print(a,t,' | '.join(c))
