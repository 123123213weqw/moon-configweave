"""Run the three complete scenarios in examples/ through the host adapter and
check their documented outcomes. Secrets are synthetic fixture values."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
SECRETS = {'ORDERS_DB_PASSWORD': 'fixture-db-pw-7731', 'PORTAL_CLIENT_SECRET': 'fixture-portal-991',
           'ACME_WEBHOOK_KEY': 'fixture-acme-442'}
checks = 0


def run(manifest):
    env = {k: v for k, v in os.environ.items() if k not in SECRETS}
    env.update(SECRETS)
    result = subprocess.run([sys.executable, '-B', str(root / 'scripts/files.py'), str(root / 'examples' / manifest)],
                            env=env, capture_output=True, text=True, encoding='utf-8', timeout=120)
    for secret in SECRETS.values():
        assert secret not in result.stdout and secret not in result.stderr, manifest + ': secret leaked'
    report = json.loads(result.stdout) if result.stdout.strip() else None
    return result.returncode, report, result.stderr.strip()


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def service():
    code, dev, _ = run('service/dev.manifest.json')
    expect(code == 0 and dev['valid'], 'dev configuration is valid')
    expect(dev['config']['service']['features'] == ['metrics', 'debugger'], 'unique array merge keeps both feature lists')
    expect(dev['config']['database']['url'] == 'postgres://orders@db.dev.internal:5432/orders', 'url interpolates the dev host')
    expect(dev['config']['database']['password'] == '***' and dev['masked'] == ['/database/password'], 'secret is masked')
    expect([l['source'] for l in dev['layers']] == ['defaults.toml', 'dev.json'], 'layers trace back to files')
    expect(dev['origins']['/database/host'] == ['defaults', 'dev'], 'override chain recorded')

    code, prod, _ = run('service/prod.manifest.json')
    expect(code == 1 and not prod['valid'], 'prod configuration is reported invalid')
    expect(prod['issues'] == [{'path': '/database/port', 'reason': 'type mismatch'}], 'wrong override is identified')
    expect(prod['origins']['/database/port'] == ['defaults', 'prod'], 'wrong override is attributed to prod.json')
    expect(prod['config']['service']['port'] == 443, 'production port applied')
    expect({'path': '/database/port', 'layer': 'defaults', 'by': 'prod'} in prod['shadowed'],
           'the wrong override is listed with the layer it shadowed')

    code, diff, _ = run('service/diff.manifest.json')
    changed = {c['path']: c for c in diff['changes']}
    expect(code == 0 and not diff['equal'], 'environments differ')
    expect(changed['/service/port']['before'] == 8080 and changed['/service/port']['after'] == 443, 'port difference reported')
    expect(changed['/service/port']['after_origins'] == ['defaults', 'prod'], 'difference carries its origins')
    expect('/database/password' not in changed, 'identical hidden secrets produce no diff entry')
    expect(changed['/database/url']['after_origins'] == ['defaults'], 'derived value change is reported with its own origin')

    code, export, _ = run('service/export-dev.manifest.json')
    expect(export['text'] == canonical(dev['redacted']), 'export text equals independent canonical JSON of the redacted config')


def ci():
    code, linux, _ = run('ci/linux.manifest.json')
    expect(code == 0 and linux['config']['job']['steps'][-1] == 'moon test --target native', 'append keeps base steps and adds platform steps')
    expect(linux['config']['matrix']['targets'] == ['js', 'wasm-gc', 'wasm-gc', 'native'], 'append strategy is visible as a duplicate target')
    expect(linux['config']['job']['env']['MOON_HOME'] == '/home/runner/.moon', 'path interpolation uses the base home')

    code, macos, _ = run('ci/macos.manifest.json')
    expect(macos['config']['matrix']['targets'] == ['js', 'wasm-gc', 'native'], 'unique strategy removes the duplicate target')
    expect(macos['config']['job']['env']['MOON_HOME'] == '/Users/runner/.moon', 'platform home propagates through the reference')
    expect(macos['origins']['/job/timeout_minutes'] == ['base', 'macos'], 'timeout override attributed to macos.json')

    code, strict, stderr = run('ci/windows-strict.manifest.json')
    expect(code == 1 and strict is None, 'strict types reject the conflicting overlay')
    expect(json.loads(stderr) == {'error': 'type-changing overlay at /job/timeout_minutes'}, 'conflict diagnostic names the path')

    code, report, _ = run('ci/windows-report.manifest.json')
    expect(code == 1 and report['issues'] == [{'path': '/job/timeout_minutes', 'reason': 'type mismatch'}], 'non-strict run reports the conflict as an issue')
    expect(report['origins']['/job/timeout_minutes'] == ['base', 'windows'], 'conflict attributed to windows.json')

    code, export, _ = run('ci/export-linux.manifest.json')
    expect(code == 0 and export['text'] == canonical(linux['redacted']), 'stable export matches independent canonical JSON')
    expect(export['text'] == export['text'].strip() and '\n' not in export['text'], 'export is a single line')


def tenants():
    code, a, _ = run('tenants/tenant-a.manifest.json')
    expect(code == 0 and a['valid'], 'tenant-a satisfies organization policy')
    expect(a['config']['auth']['provider'] == 'oidc' and a['config']['auth']['issuer'] == 'https://login.acme.example', 'org layer applies to tenant-a')
    expect(a['config']['app']['limits'] == {'requests_per_minute': 1200, 'storage_gb': 50}, 'three-level merge resolved')
    expect(a['masked'] == ['/auth/client_secret', '/integrations/webhook/signing_key'], 'both secrets masked')

    code, b, _ = run('tenants/tenant-b.manifest.json')
    expect(code == 1 and [i['reason'] for i in b['issues']] == ['above maximum', 'not in enum'], 'tenant-b violations listed')
    expect(b['origins']['/auth/provider'] == ['defaults', 'org-acme', 'tenant-b'], 'provider downgrade attributed to tenant-b.json')
    expect(b['config']['integrations']['webhook']['signing_key'] == '***', 'hardcoded key never printed')
    expect({'path': '/auth/provider', 'layer': 'org-acme', 'by': 'tenant-b'} in b['shadowed'],
           'the provider downgrade names the organization policy it overrode')

    code, audit, _ = run('tenants/audit.manifest.json')
    kinds = {(c['type'], c['path']) for c in audit['changes']}
    expect(('changed', '/auth/provider') in kinds and ('changed', '/app/limits/requests_per_minute') in kinds, 'tenant differences listed')
    masked = [c for c in audit['changes'] if c['type'] == 'masked_override']
    expect(masked == [{'path': '/integrations/webhook/signing_key', 'type': 'masked_override',
                       'before_origins': ['defaults', 'org-acme'], 'after_origins': ['defaults', 'org-acme', 'tenant-b']}],
           'secret override located by origin without revealing values')
    expect(all('before' not in c and 'after' not in c for c in masked), 'masked override carries no values')


service()
ci()
tenants()
print('Scenarios passed: service environments, CI platforms, tenant audit;', checks, 'checks')
