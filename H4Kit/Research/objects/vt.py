import sys; sys.path.insert(0,'.')
from pe import *
for v in sys.argv[1:]:
    a=int(v,16); print(v, hex(u32(a+0xd4)), hex(u32(a+0x90)))
