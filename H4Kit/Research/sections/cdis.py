import sys,re; from reg import fn
KNOWN={0x879420:'STR16',0x40d570:'(err)',0x8e0001:'(throw)',0x401ce0:'(strinit)',0x8d98a0:'new',0x8dbd90:'free'}
def cshow(a):
    ins=fn(a,1500); out=[]; last_push=None; seen=set()
    for k,(x,i) in enumerate(ins):
        if x in seen: continue
        seen.add(x)
        m=re.match(r'pushl \$0x([0-9a-f]+)$',i)
        if m: last_push=int(m.group(1),16)
        if re.match(r'calll \*0x18\(%e..\)',i):
            out.append('%x READ %s'%(x,last_push)); continue
        m=re.match(r'calll 0x([0-9a-f]+)$',i)
        if m:
            t=int(m.group(1),16)
            if t in (0x40d570,0x8e0001,0x401ce0): continue
            out.append('%x CALL %s'%(x,KNOWN.get(t,hex(t)))); continue
        if i.startswith('calll'): out.append('%x %s'%(x,i)); continue
        if re.match(r'(cmp|test|j|ret|and[lwb] \$0x(ff|ffff)\b|mov[bwl] .*, 0x[0-9a-f]+\(%e[sd]i\))',i): out.append('%x %s'%(x,i))
    return out
for a in sys.argv[1:]: print('==',a); print('\n'.join(cshow(int(a,16))))
