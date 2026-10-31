import sys,re; sys.path.insert(0,'.')
from hdr import *
def show(name,a,b):
    d=load(MAPS+name); h=header(d); s=d[h[5]+a:h[5]+b]
    print(name,a,b); print(re.sub(rb'[^\x20-\x7e]',lambda m:b'<%02x>'%m.group(0)[0],s).decode())
if __name__=='__main__':
    show(sys.argv[1],int(sys.argv[2]),int(sys.argv[3]))
