import sys,re
sys.path.insert(0,'.')
from x86dis import fn
SKIP=('0x40d570','0x8e0001','0x8e008b','0x40dbf0','0x8dbd90','0x401ce0','0x4e9990')
def skim(a):
    ins=fn(a); out=[]
    for k,(ad,i) in enumerate(ins):
        if re.match(r'calll \*0x18\(',i):
            n=None
            for q in range(k-1,max(k-12,0),-1):
                if ins[q][1].startswith('call'): break
                m=re.match(r'pushl \$(-?0x[0-9a-f]+)$',ins[q][1])
                if m: n=m.group(1);break
            out.append('%x READ(%s)'%(ad,n))
        elif i.startswith('call') and any(s in i for s in SKIP): pass
        elif i.startswith('call') or re.match(r'cmpl? \$',i) or re.match(r'j[a-z]+ ',i) or i.startswith('ret') or (re.search(r'\$0x[0-9a-f]{6}',i) and 'push' in i and '0x9cf' not in i and '0x95' not in i):
            out.append('%x %s'%(ad,i))
    return out
if __name__=='__main__':
    for a in sys.argv[1:]:
        print('==',a); print('\n'.join(skim(int(a,16))))
