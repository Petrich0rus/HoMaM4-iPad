import struct,os,sys,collections
d='advobj/adv_object'
def parse(b):
    p=0
    def u16():
        nonlocal p; v=struct.unpack_from('<H',b,p)[0]; p+=2; return v
    def u8():
        nonlocal p; v=b[p]; p+=1; return v
    def s16():
        nonlocal p; n=u16(); s=b[p:p+n].decode('latin1'); p+=n; return s
    ver=u16(); ot=u8()
    edge=u16() if ver>=3 else 0
    w=u16();h=u16()
    def bits(n):
        nonlocal p; p+=(n+7)//8
    bits(w*h)
    if edge<1: bits(w*h)
    else: bits((h+1)*w); bits((w+1)*h)
    if ver>5:
        bits(2*(h+1)*w); bits(2*(w+1)*h); p+=(w+1)*(h+1)
    cl=[]
    if ver>1:
        u16()
        for _ in range(3): cl.append((u16(),s16()))
    return ver,ot,cl
res=collections.defaultdict(list)
for f in sorted(os.listdir(d)):
    try: ver,ot,cl=parse(open(d+'/'+f,'rb').read())
    except Exception as e: print('ERR',f,e); continue
    res[(ot,tuple(c[0] for c in cl),tuple(c[1] for c in cl))].append(f)
for k in sorted(res): print(k,len(res[k]),res[k][0])
