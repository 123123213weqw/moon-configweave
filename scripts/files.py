"""Read JSON/TOML layers using Python 3.11+; MoonBit performs merge and validation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib

def load(request, base):
    request = dict(request)
    if request.get('operation') == 'diff':
        request['old'] = load(request['old'], base)
        request['new'] = load(request['new'], base)
        return request
    layers = []
    for layer in request['layers']:
        layer = dict(layer)
        if 'file' in layer:
            path = (base / layer.pop('file')).resolve()
            # Layer files are read only; keep all referenced files within the manifest directory.
            if not path.is_relative_to(base):
                raise ValueError('Layer file leaves manifest directory')
            if path.stat().st_size > 4*1024*1024:
                raise ValueError('Layer file exceeds 4 MiB')
            if path.suffix == '.toml':
                with path.open('rb') as stream: layer['value'] = tomllib.load(stream)
            elif path.suffix == '.json':
                layer['value'] = json.loads(path.read_text(encoding='utf-8'))
            else:
                raise ValueError('Only JSON and TOML layer files are supported')
        layers.append(layer)
    request['layers'] = layers
    environment = dict(request.get('env', {}))
    for name in request.pop('allow_environment', []):
        if name in os.environ: environment[name] = os.environ[name]
    request['env'] = environment
    return request

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    file = args.manifest.resolve()
    request = load(json.loads(file.read_text(encoding='utf-8')), file.parent)
    cli = Path(__file__).resolve().parents[1] / '_build/js/debug/build/cmd/main/main.js'
    result = subprocess.run(['node', str(cli), '-'], input=json.dumps(request,allow_nan=False),
        capture_output=True, text=True, encoding='utf-8', timeout=60)
    if result.returncode:
        raise RuntimeError(result.stdout or result.stderr)
    report = json.loads(result.stdout)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report.get('valid', True) else 1

if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        raise SystemExit(main())
    except Exception as error:
        # Avoid printing input values or environment contents on failures.
        print(type(error).__name__ + ': input could not be processed', file=sys.stderr)
        raise SystemExit(1)
