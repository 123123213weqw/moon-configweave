"""Scale validation and throughput benchmarks with deterministic synthetic data.

    python -B scripts/bench.py          # correctness at scale + timing table (median of 3)
    python -B scripts/bench.py --check  # correctness only, for CI

Timings are end-to-end CLI runs (node startup included) on this machine;
they are recorded observations, not performance targets. The large merge
case is also compared against the independent Python oracle.
"""
import json
import random
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
CLI = str(root / '_build/js/debug/build/cmd/main/main.js')
sys.path.insert(0, str(root / 'scripts'))
from reference import Oracle   # independent merge semantics, reused read-only


random.seed(20261018)


def run(request):
    result = subprocess.run(['node', CLI, '-'], input=json.dumps(request), capture_output=True,
                            text=True, encoding='utf-8', timeout=300)
    if result.returncode not in (0, 2):
        raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)


def wide_layers(layer_count, keys):
    layers = []
    base = {}
    for i in range(keys):
        section, leaf = 'svc%02d' % (i % 40), 'key%04d' % i
        base.setdefault(section, {})[leaf] = i
    layers.append({'name': 'base', 'value': base})
    for layer in range(1, layer_count):
        overlay = {}
        for i in range(0, keys, 7):
            section, leaf = 'svc%02d' % (i % 40), 'key%04d' % i
            overlay.setdefault(section, {})[leaf] = i + layer * 100000
        layers.append({'name': 'override%d' % layer, 'value': overlay})
    return layers


def deep_config(depth):
    value = {'leaf': 1}
    for i in range(depth):
        value = {'level%02d' % i: value}
    return value


def main():
    check_only = '--check' in sys.argv
    rows = []

    def measure(label, request, oracle_expected=None):
        best = None
        for _ in range(1 if check_only else 3):
            start = time.perf_counter()
            result = run(request)
            elapsed = (time.perf_counter() - start) * 1000
            best = elapsed if best is None else min(best, elapsed)
        if oracle_expected is not None:
            assert result['config'] == oracle_expected, label
        rows.append((label, best))

    wide = wide_layers(12, 2000)
    wide_request = {'layers': wide}
    oracle = Oracle(wide_request)
    measure('merge 12 layers x 2000 keys', wide_request, oracle.redacted)

    measure('export flat of the same tree', {'operation': 'export', 'format': 'flat', 'layers': wide})

    refs = {'name': 'ref', 'value': {'v%d' % i: '${config:/svc00/key0000}-%d' % i for i in range(1000)}}
    base_ref = {'name': 'base', 'value': dict(wide[0]['value'])}
    measure('1000 interpolation references', {'layers': [base_ref, refs]})

    deep_request = {'layers': [{'name': 'a', 'value': deep_config(100)}, {'name': 'b', 'value': deep_config(100)}]}
    deep_expected = Oracle(deep_request)
    measure('merge at nesting depth 100', deep_request, deep_expected.redacted)

    if check_only:
        print('Scale check passed: 24k-key merge, 1000 references and depth-100 merge agree with the oracle')
        return
    print('| Case | Median wall time (ms) |')
    print('| --- | ---: |')
    for label, elapsed in rows:
        print('| %s | %s |' % (label, 'n/a' if elapsed is None else '%.0f' % elapsed))
    print()
    print('End-to-end CLI runs (node startup included), best of three, on this machine; recorded observations, not targets.')


if __name__ == '__main__':
    main()
