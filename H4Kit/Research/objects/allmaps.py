import sys,glob,gzip,collections,struct
sys.path.insert(0,'.')
from chain import *
d="/Volumes/Heroes of might and magic IV/Heroes IV.app/Contents/SharedSupport/prefix/drive_c/GOG Games/HoMM 4 Complete/maps/"
miss=collections.Counter(); tot=0; full=0
for p in sorted(glob.glob(d+'**/*.h4c',recursive=True)):
    try:
        raw=open(p,'rb').read(); body=gzip.decompress(raw[15:])
    except Exception as e: print('ERR',p,e); continue
    o=find_start(body)
    if o is None: print('nostart',p); continue
    seq,n,at,why=walk(body,o)
    tot+=1
    if why=='complete': full+=1
    else: miss[why.split(' ',4)[-1] if 'reader' in why else why[:50]]+=1
print(tot,full); 
for k,v in miss.most_common(): print(v,k)
print('---asserts')
for p in sorted(glob.glob(d+'**/*.h4c',recursive=True)):
    raw=open(p,'rb').read(); body=gzip.decompress(raw[15:])
    o=find_start(body)
    seq,n,at,why=walk(body,o)
    if why.startswith('assert') or why=='missing' or 'unknown' in why:
        print(p.split('/')[-1],why,'prev:',seq[-1][1:4] if seq else None, 'at',at, body[at:at+60])
