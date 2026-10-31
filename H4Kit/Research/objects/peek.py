import sys,gzip,glob
sys.path.insert(0,'.')
from probe import *
name,off=sys.argv[1],int(sys.argv[2])
for p,b,v in bodies():
    if p.endswith(name): print(v); print(b[off:off+int(sys.argv[3])].hex(' '))
