import sys; from reg import fn
def show(a):
    out=[]
    for x,i in fn(a,600):
        if any(k in i for k in ('%fs','nop')): continue
        out.append('%x %s'%(x,i))
    return out
for a in sys.argv[1:]: print('==',a); print('\n'.join(show(int(a,16))))
