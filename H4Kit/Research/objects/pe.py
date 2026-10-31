import struct
D=open('/private/tmp/claude-501/-Users-petrichorus-Documents-Claude-Workspace-REA/b0a8b84f-1fe9-498d-b633-5bb45dbda9c4/scratchpad/objects/heroes4.exe','rb').read()
e=struct.unpack_from('<I',D,0x3c)[0]
nsec=struct.unpack_from('<H',D,e+6)[0]; osz=struct.unpack_from('<H',D,e+20)[0]
base=struct.unpack_from('<I',D,e+24+28)[0]
secs=[]
for i in range(nsec):
    o=e+24+osz+i*40
    vs,va,rs,ro=struct.unpack_from('<IIII',D,o+8)
    secs.append((base+va,vs,ro,rs))
def off(a):
    for va,vs,ro,rs in secs:
        if va<=a<va+max(vs,rs): return ro+a-va
    raise KeyError(hex(a))
def u32(a): return struct.unpack_from('<I',D,off(a))[0]
def rd(a,n): o=off(a); return D[o:o+n]
def cstr(a):
    o=off(a); e=D.index(b'\0',o); return D[o:e].decode('latin1')
