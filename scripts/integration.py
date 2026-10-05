import json
import os
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='configweave-integration-') as temporary:
    base=Path(temporary)
    (base/'base.toml').write_text('[server]\nport = 8080\nname = "local"\n[database]\npassword = "${env:CONFIG_TEST_KEY}"\n',encoding='utf-8')
    (base/'override.json').write_text('{"server":{"port":9000}}',encoding='utf-8')
    request={'layers':[{'name':'toml','file':'base.toml'},{'name':'json','file':'override.json'}],
        'allow_environment':['CONFIG_TEST_KEY'],'secret_env':['CONFIG_TEST_KEY']}
    (base/'manifest.json').write_text(json.dumps(request),encoding='utf-8')
    env=os.environ.copy(); env['CONFIG_TEST_KEY']='fixture-secret'
    result=subprocess.run(['python','-B',str(root/'scripts/files.py'),str(base/'manifest.json')],env=env,capture_output=True,text=True,encoding='utf-8')
    assert result.returncode == 0, result.stderr
    assert 'fixture-secret' not in result.stdout
    report=json.loads(result.stdout)
    assert report['config']['server']=={'port':9000,'name':'local'}
    assert report['config']['database']['password']=='***'
    print('Config file integration: real TOML/JSON layer loading, environment allowlist and redaction passed')
