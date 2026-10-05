"""Independent Python standard library oracles; deterministic synthetic data."""
import csv, datetime, hashlib, heapq, io, json, math, random, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
random.seed(20261005)
def run(request):
    result = subprocess.run(['node',str(root/'_build/js/debug/build/cmd/main/main.js'),'-'],
        input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=30)
    if result.returncode: raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)

for i in range(20):
    a,b,c = random.randint(0,100),random.randint(0,100),random.randint(0,100)
    report = run({'layers':[{'name':'base','value':{'a':a,'nested':{'b':b}}},{'name':'override','value':{'nested':{'c':c}}}]})
    assert report['config'] == {'a':a,'nested':{'b':b,'c':c}}
print('Independent configuration oracle: 20 nested merge preservation cases passed')
