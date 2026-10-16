import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[1]

def files(manifest, env):
    return subprocess.run([sys.executable,'-B',str(root/'scripts/files.py'),str(manifest)],env=env,capture_output=True,text=True,encoding='utf-8')

with tempfile.TemporaryDirectory(prefix='configweave-integration-') as temporary:
    base=Path(temporary)
    (base/'base.toml').write_text('[server]\nport = 8080\nname = "local"\n[database]\npassword = "${env:CONFIG_TEST_KEY}"\n',encoding='utf-8')
    (base/'override.json').write_text('{"server":{"port":9000}}',encoding='utf-8')
    request={'layers':[{'name':'toml','file':'base.toml'},{'name':'json','file':'override.json'}],
        'allow_environment':['CONFIG_TEST_KEY'],'secret_env':['CONFIG_TEST_KEY']}
    (base/'manifest.json').write_text(json.dumps(request),encoding='utf-8')
    env=os.environ.copy(); env['CONFIG_TEST_KEY']='fixture-secret'
    result=files(base/'manifest.json',env)
    assert result.returncode == 0, result.stderr
    assert 'fixture-secret' not in result.stdout
    report=json.loads(result.stdout)
    assert report['config']['server']=={'port':9000,'name':'local'}
    assert report['config']['database']['password']=='***'
    assert report['masked']==['/database/password']
    assert [layer['source'] for layer in report['layers']]==['base.toml','override.json']
    # Without the allowlisted variable the engine rejects the request and the adapter
    # relays only the engine's value-free message.
    del env['CONFIG_TEST_KEY']
    missing=files(base/'manifest.json',env)
    assert missing.returncode == 1 and missing.stdout == ''
    assert json.loads(missing.stderr)=={'error':'missing environment variable: CONFIG_TEST_KEY'}
    # Layer files outside the manifest directory are refused before anything is read.
    (base/'escape.json').write_text(json.dumps({'layers':[{'name':'x','file':'../outside.json'}]}),encoding='utf-8')
    escape=files(base/'escape.json',env)
    assert escape.returncode == 1 and 'could not be processed' in escape.stderr
    print('Config file integration: real TOML/JSON layer loading, environment allowlist, redaction, source labels and adapter error handling passed')
