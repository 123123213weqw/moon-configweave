"""Read JSON/TOML layers using Python 3.11+; MoonBit performs merge and validation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib

def read_layer(base, name):
    """Parse one JSON or TOML layer file; files are read only and must stay inside the manifest directory."""
    path = (base / name).resolve()
    if not path.is_relative_to(base):
        raise ValueError('Layer file leaves manifest directory')
    if path.stat().st_size > 4*1024*1024:
        raise ValueError('Layer file exceeds 4 MiB')
    if path.suffix == '.toml':
        with path.open('rb') as stream: return tomllib.load(stream)
    if path.suffix == '.json':
        return json.loads(path.read_text(encoding='utf-8'))
    raise ValueError('Only JSON and TOML layer files are supported')

def load(request, base):
    request = dict(request)
    if request.get('operation') == 'diff':
        request['old'] = load(request['old'], base)
        request['new'] = load(request['new'], base)
        return request
    layers = []
    for layer in request['layers']:
        layer = dict(layer)
        if 'dir' in layer:
            # A directory expands to one layer per .json/.toml file in name order (conf.d style);
            # each generated layer is named after its file and labelled with it as source.
            directory = (base / layer.pop('dir')).resolve()
            if not directory.is_relative_to(base) or not directory.is_dir():
                raise ValueError('Layer directory must be inside the manifest directory')
            prefix = layer.pop('name', directory.relative_to(base).as_posix())
            for entry in sorted(p for p in directory.iterdir() if p.is_file() and p.suffix in ('.json', '.toml')):
                relative = entry.relative_to(base).as_posix()
                layers.append({**layer, 'name': prefix + '/' + entry.name, 'source': relative, 'value': read_layer(base, relative)})
            continue
        if 'file' in layer:
            name = layer.pop('file')
            layer['value'] = read_layer(base, name)
            layer.setdefault('source', name)
        layers.append(layer)
    request['layers'] = layers
    environment = dict(request.get('env', {}))
    for name in request.pop('allow_environment', []):
        if name in os.environ: environment[name] = os.environ[name]
    request['env'] = environment
    return request

class EngineError(Exception):
    """The engine rejected the request; its message names paths, never values."""

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    file = args.manifest.resolve()
    request = load(json.loads(file.read_text(encoding='utf-8')), file.parent)
    cli = Path(__file__).resolve().parents[1] / '_build/js/debug/build/cmd/main/main.js'
    result = subprocess.run(['node', str(cli), '-'], input=json.dumps(request,allow_nan=False),
        capture_output=True, text=True, encoding='utf-8', timeout=60)
    if result.returncode not in (0, 2):   # 2 is a report with issues, relayed below
        try:
            raise EngineError(json.loads(result.stdout)['error'])
        except (ValueError, KeyError, TypeError):
            raise RuntimeError('engine failed') from None
    report = json.loads(result.stdout)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report.get('valid', True) else 2   # 1 is reserved for rejected requests

if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        raise SystemExit(main())
    except EngineError as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        raise SystemExit(1)
    except Exception as error:
        # Avoid printing input values or environment contents on failures.
        print(type(error).__name__ + ': input could not be processed', file=sys.stderr)
        raise SystemExit(1)
