import sys,re
exec(open('asm.py').read().split("for a in sys.argv")[0])
def clean(a):
    out=[];skip=0
    ls=show(a)
    i=0
    while i<len(ls):
        l=ls[i]; t=l.split(' ',1)[1] if ' ' in l else ''
        if re.match(r'(popl|pushl %e..|pushl \$-0x1|subl \$0x[0-9a-f]+, %esp|addl \$0x[0-9a-f]+, %esp|nop|xorb %al, %al$)',t) : i+=1; continue
        # error throw pattern
        if t.startswith('leal') and i+4<len(ls) and '40d570' in ls[i+1]:
            # skip the 5-line throw
            i+=5; 
            while i<len(ls) and ('9cf238' in ls[i] or '8e0001' in ls[i] or re.search(r'pushl %e.x$',ls[i])): i+=1
            out.append('   [throw-if-short]'); continue
        m=re.match(r'calll \*0x18\(',t)
        if m: out.append(l+'   <== READ'); i+=1; continue
        out.append(l); i+=1
    return out
for a in sys.argv[1:]: print('==',a); print('\n'.join(clean(int(a,16))))
