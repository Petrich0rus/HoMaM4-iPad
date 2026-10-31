import sys,re,subprocess
# compact disasm: drop exception-handling noise
out=subprocess.run(['python3','asm.py']+sys.argv[1:],capture_output=True,text=True).stdout
for l in out.split('\n'):
    if l.startswith('=='): print(l); continue
    print(l[:64])
