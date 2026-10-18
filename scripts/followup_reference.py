"""Independent follow-up oracles over synthetic deterministic inputs."""
import collections,copy,hashlib,json,math,random,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
random.seed(20261018)
def run(request, error=False):
    result=subprocess.run(['node',str(root/'_build/js/debug/build/cmd/main/main.js'),'-'],input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=60)
    if error:
        assert result.returncode==1,(result.returncode,result.stdout); return
    assert result.returncode in (0,2),(result.returncode,result.stdout,result.stderr)
    return json.loads(result.stdout)

for i in range(20):
    secret='fixture-hidden-'+str(i)
    report=run({'operation':'audit','layers':[{'name':'base','value':{'port':i,'secret':{'deep':secret}}}],'sensitive':['/secret'],'reveal':True})
    assert secret not in json.dumps(report)
    assert {entry['path'] for entry in report['paths']}=={'','/port','/secret'}
    assert next(p for p in report['paths'] if p['path']=='/secret')['type']=='redacted'
    assert report['values_included'] is False
print('Configuration audit: 20 value-free reports and masked-subtree boundaries passed')
