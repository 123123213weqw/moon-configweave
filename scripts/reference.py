"""Independent Python standard library oracle; deterministic synthetic data.

One hundred environment/tenant configuration sets are merged by a separate
re-implementation of the documented semantics and compared with the engine on
merged values, origins, masked paths, constraint verdicts, canonical export
text, key-order invariance, diff output and secret masking. Failure paths are
checked afterwards.
"""
import json
import random
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
random.seed(20261016)
CLI = str(root / '_build/js/debug/build/cmd/main/main.js')


def run(request):
    result = subprocess.run(['node', CLI, '-'], input=json.dumps(request), capture_output=True,
                            text=True, encoding='utf-8', timeout=30)
    if result.returncode not in (0, 2):          # 2 is a report with constraint issues
        raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout), result.stdout


def fails(request):
    try:
        run(request)
        return False
    except RuntimeError:
        return True


# --- independent semantics -------------------------------------------------

def esc(key):
    return key.replace('~', '~0').replace('/', '~1')


def note(origins, path, source):
    history = origins.setdefault(path, [])
    if not history or history[-1] != source:
        history.append(source)


def track(value, path, source, origins):
    note(origins, path, source)
    if isinstance(value, dict):
        for k, v in value.items():
            track(v, path + '/' + esc(k), source, origins)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            track(v, path + '/' + str(i), source, origins)
    return value


def strategy_at(arrays, path):
    """arrays is a mode name or {"default": mode, mode: [pointers]}; per-path pointers match exactly."""
    if isinstance(arrays, str):
        return arrays
    for mode, pointers in arrays.items():
        if mode != 'default' and path in pointers:
            return mode
    return arrays.get('default', 'replace')


def merge(base, overlay, arrays, origins, path, source, shadowed=None):
    note(origins, path, source)
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for k, v in overlay.items():
            child = path + '/' + esc(k)
            out[k] = merge(base[k], v, arrays, origins, child, source, shadowed) if k in base else track(v, child, source, origins)
        return out
    mode = strategy_at(arrays, path)
    if isinstance(base, list) and isinstance(overlay, list) and mode != 'replace':
        out = list(base)
        for v in overlay:
            if mode == 'append' or v not in out:
                track(v, path + '/' + str(len(out)), source, origins)
                out.append(v)
        return out
    if shadowed is not None and base != overlay:
        history = origins[path]
        if len(history) >= 2 and history[-2] != source:
            shadowed.append((path, history[-2], source))
    return track(overlay, path, source, origins)


def at(root_value, pointer):
    current = root_value
    for part in pointer.split('/')[1:] if pointer else []:
        part = part.replace('~1', '/').replace('~0', '~')
        current = current[int(part)] if isinstance(current, list) else current[part]
    return current


def under(path, parent):
    return path == parent or path.startswith(parent + '/')


class Oracle:
    def __init__(self, request):
        self.arrays = request.get('arrays', 'replace')
        self.env = request.get('env', {})
        self.secret_env = set(request.get('secret_env', []))
        self.sensitive = request.get('sensitive', [])
        self.sensitive_keys = set(request.get('sensitive_keys', []))
        self.origins = {}
        self.tainted = set()
        self.shadowed = []
        merged = {}
        for layer in request['layers']:
            merged = merge(merged, layer['value'], self.arrays, self.origins, '', layer['name'], self.shadowed)
        self.shadowed = [{'path': p, 'layer': l, 'by': b} for p, l, b in
                         sorted(self.shadowed, key=lambda e: (e[0].encode('utf-16-be'), e[1].encode('utf-16-be')))]
        self.root = merged
        self.resolved = self.resolve('')
        self.masked = []
        self.redacted = self.redact(self.resolved, '')
        self.masked.sort(key=lambda p: p.encode('utf-16-be'))
        self.issues = [issue for issue in map(self.check, request.get('constraints', [])) if issue]

    def designated(self, path):
        last = path.rsplit('/', 1)[-1].replace('~1', '/').replace('~0', '~') if path else ''
        return any(under(path, s) for s in self.sensitive) or (path != '' and last in self.sensitive_keys)

    def is_masked(self, path):
        return self.designated(path) or path in self.tainted

    def hides_secret(self, path):
        """Any designated path strictly below `path` in the merged tree."""
        def below(value, prefix):
            if isinstance(value, dict):
                return any(self.designated(prefix + '/' + esc(k)) or below(v, prefix + '/' + esc(k)) for k, v in value.items())
            if isinstance(value, list):
                return any(self.designated(prefix + '/' + str(i)) or below(v, prefix + '/' + str(i)) for i, v in enumerate(value))
            return False
        return below(at(self.root, path), path)

    def present(self, path):
        try:
            at(self.root, path)
            return True
        except (KeyError, IndexError, TypeError, ValueError):
            return False

    def reference(self, token, owner):
        target, has_fallback, fallback = token.partition(':-')
        if target.startswith('env:'):
            name = target[4:]
            if name in self.env:
                if name in self.secret_env:
                    self.tainted.add(owner)
                return self.env[name]
            if has_fallback:
                return fallback
            raise KeyError(name)
        path = target[len('config:'):]
        if not self.present(path):
            if has_fallback:
                return fallback
            raise KeyError(path)
        value = self.resolve(path)
        if self.is_masked(path) or self.hides_secret(path) or any(under(t, path) for t in self.tainted):
            self.tainted.add(owner)
        return value

    def render(self, value):
        if isinstance(value, str):
            return value
        if isinstance(value, bool):
            return 'true' if value else 'false'
        return json.dumps(value)

    def interpolate(self, text, owner):
        parts = re.split(r'\$\{([^}]*)\}', text)
        if len(parts) == 3 and parts[0] == '' and parts[2] == '':
            return self.reference(parts[1], owner)
        return ''.join(part if i % 2 == 0 else self.render(self.reference(part, owner)) for i, part in enumerate(parts))

    def resolve(self, path):
        value = at(self.root, path)
        if isinstance(value, str):
            return self.interpolate(value, path)
        if isinstance(value, dict):
            return {k: self.resolve(path + '/' + esc(k)) for k in value}
        if isinstance(value, list):
            return [self.resolve(path + '/' + str(i)) for i in range(len(value))]
        return value

    def redact(self, value, path):
        if self.is_masked(path):
            self.masked.append(path)
            return '***'
        if isinstance(value, dict):
            return {k: self.redact(v, path + '/' + esc(k)) for k, v in value.items()}
        if isinstance(value, list):
            return [self.redact(v, path + '/' + str(i)) for i, v in enumerate(value)]
        return value

    def check(self, constraint):
        path = constraint['path']
        try:
            value = at(self.resolved, path)
        except (KeyError, IndexError):
            return {'path': path, 'reason': 'required value missing'} if constraint.get('required') else None
        kind = {bool: 'boolean', int: 'number', float: 'number', str: 'string', list: 'array', dict: 'object',
                type(None): 'null'}[type(value)]
        expected = constraint.get('type', 'any')
        length = len(value) if kind in ('string', 'array') else None
        reason = None
        if expected != 'any' and expected != kind:
            reason = 'type mismatch'
        elif 'enum' in constraint and value not in constraint['enum']:
            reason = 'not in enum'
        elif 'pattern' in constraint and kind != 'string':
            reason = 'pattern requires string'
        elif 'pattern' in constraint and not re.search(constraint['pattern'], value):
            reason = 'pattern mismatch'
        elif 'min_length' in constraint and length is None:
            reason = 'length requires string or array'
        elif 'min_length' in constraint and length < constraint['min_length']:
            reason = 'below minimum length'
        elif 'max_length' in constraint and length is None:
            reason = 'length requires string or array'
        elif 'max_length' in constraint and length > constraint['max_length']:
            reason = 'above maximum length'
        elif 'min' in constraint and kind != 'number':
            reason = 'numeric minimum requires number'
        elif 'min' in constraint and value < constraint['min']:
            reason = 'below minimum'
        elif 'max' in constraint and kind != 'number':
            reason = 'numeric maximum requires number'
        elif 'max' in constraint and value > constraint['max']:
            reason = 'above maximum'
        return {'path': path, 'reason': reason} if reason else None


# --- synthetic tenant configuration sets -----------------------------------

def leaf_paths(value, path=''):
    if isinstance(value, dict):
        for k, v in value.items():
            yield from leaf_paths(v, path + '/' + esc(k))
    elif not isinstance(value, list):
        yield path, value


def random_scalar():
    return random.choice([random.randint(0, 999), 'v' + str(random.randint(0, 99)), random.choice([True, False])])


KEYS = ['alpha', 'beta', 'gamma', 'delta', 'eps', 'zeta', 'eta', 'theta', '键', 'ключ', 'café', 'a/b', 'c~d', '~1', 'x y']


def random_tree(depth):
    tree = {}
    for key in random.sample(KEYS, random.randint(2, 5)):
        if depth < 3 and random.random() < 0.45:
            tree[key] = random_tree(depth + 1)
        elif random.random() < 0.15:
            tree[key] = [random.randint(0, 9) for _ in range(random.randint(1, 4))]
        else:
            tree[key] = random_scalar()
    return tree


def overlay_for(defaults, case):
    """Override some leaves with same-typed values and add a few new keys."""
    result = {}
    for path, value in leaf_paths(defaults):
        if random.random() < 0.35:
            parts = [part.replace('~1', '/').replace('~0', '~') for part in path.split('/')[1:]]
            node = result
            for part in parts[:-1]:
                node = node.setdefault(part, {})
            node[parts[-1]] = (random.randint(0, 999) if isinstance(value, int) and not isinstance(value, bool)
                               else 'v' + str(random.randint(0, 99)) if isinstance(value, str)
                               else not value if isinstance(value, bool) else value)
    if random.random() < 0.5:
        result['extra' + str(case)] = random_tree(2)
    return result


def shuffle_keys(value):
    if isinstance(value, dict):
        keys = list(value)
        random.shuffle(keys)
        return {k: shuffle_keys(value[k]) for k in keys}
    if isinstance(value, list):
        return [shuffle_keys(v) for v in value]
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def flatten(value, path=''):
    if isinstance(value, dict) and value:
        for k, v in value.items():
            yield from flatten(v, path + '/' + esc(k))
    elif isinstance(value, list) and value:
        for i, v in enumerate(value):
            yield from flatten(v, path + '/' + str(i))
    else:
        yield path, value


def infer_constraints(request, max_enum=8):
    """Constraints derived from the resolved values observed after every layer, as documented."""
    def kind_of(v):
        return {bool: 'boolean', int: 'number', float: 'number', str: 'string', list: 'array', dict: 'object', type(None): 'null'}[type(v)]
    observations = {}
    layers = request['layers']
    for k in range(1, len(layers) + 1):
        prefix = Oracle({**request, 'layers': layers[:k]})
        for pointer, leaf in flatten(prefix.resolved):
            if prefix.is_masked(pointer):
                continue
            observations.setdefault(pointer, []).append(leaf)
    constraints = []
    for path in sorted(observations, key=lambda p: p.encode('utf-16-be')):
        seen = observations[path]
        constraint = {'path': path, 'required': True}
        kinds = {kind_of(v) for v in seen if v is not None}
        if len(kinds) == 1:
            kind = kinds.pop()
            constraint['type'] = kind
            if kind == 'number':
                numbers = [v for v in seen if v is not None]
                constraint['min'], constraint['max'] = min(numbers), max(numbers)
            if kind == 'string':
                values = sorted({v for v in seen if isinstance(v, str)}, key=lambda t: t.encode('utf-16-be'))
                if 1 <= len(values) <= max_enum:
                    constraint['enum'] = values
        constraints.append(constraint)
    return constraints


def render_dotenv(value):
    """Returns (text, collided). Mirrors the documented key and value rules."""
    keys, lines = {}, []
    for pointer, leaf in flatten(value):
        key = '_'.join(''.join(c.upper() if c.isascii() and c.isalnum() else '_' for c in seg.replace('~1', '/').replace('~0', '~'))
                       for seg in pointer.split('/')[1:])
        if key in keys:
            return None, True
        keys[key] = leaf
    for key in sorted(keys):
        leaf = keys[key]
        bare = isinstance(leaf, str) and leaf != '' and not any(c in leaf for c in ' \t\n\r"\'#=')
        lines.append(key + '=' + (leaf if bare else canonical(leaf)))
    return '\n'.join(lines) + '\n', False


def array_paths(value, path=''):
    if isinstance(value, dict):
        for k, v in value.items():
            yield from array_paths(v, path + '/' + esc(k))
    elif isinstance(value, list):
        yield path


def build_case(case):
    defaults = random_tree(0)
    names = ['defaults', 'org', 'tenant', 'override'][:random.randint(2, 4)]
    layers = [{'name': 'defaults', 'value': defaults}]
    for name in names[1:]:
        layers.append({'name': name, 'value': overlay_for(defaults, case)})
    request = {'layers': layers, 'arrays': random.choice(['replace', 'append', 'unique'])}
    if random.random() < 0.4:
        # Per-path strategies: assign some array paths explicitly, keep a default for the rest.
        arrays = {'default': random.choice(['replace', 'append', 'unique'])}
        for pointer in {p for layer in layers for p in array_paths(layer['value'])}:
            if random.random() < 0.6:
                arrays.setdefault(random.choice(['replace', 'append', 'unique']), []).append(pointer)
        request['arrays'] = arrays
    merged = {}
    for layer in layers:
        merged = merge(merged, layer['value'], request['arrays'], {}, '', layer['name'])
    plain = list(leaf_paths(merged))
    env, secret_env, secrets = {}, [], []
    for i in range(random.randint(0, 3)):
        name = 'E' + str(i)
        if random.random() < 0.5:
            env[name] = 'secret-%d-%d' % (case, i)
            secret_env.append(name)
            secrets.append(env[name])
        else:
            env[name] = 'public-%d-%d' % (case, i)
    request['env'], request['secret_env'] = env, secret_env
    # Plant references on the last layer; targets are untouched plain leaves so no chains form.
    last = layers[-1]['value']
    targets = [p for p, v in plain]
    referenced = set()
    for i in range(random.randint(0, 4)):
        target = random.choice(targets)
        if random.random() < 0.4 and env:
            token = 'env:' + random.choice(list(env))
        else:
            token = 'config:' + target
            referenced.add(target)
        if random.random() < 0.3:
            # Fallbacks: an absent target with a default, or a present target whose default must be ignored.
            token = random.choice(['env:ABSENT' + str(i) + ':-dflt' + str(i), 'config:/absent' + str(i) + ':-dflt' + str(i),
                                   token + ':-ignored'])
        text = '${' + token + '}' if random.random() < 0.6 else 'pre-${' + token + '}-post'
        last['ref' + str(i)] = text
    sensitive = []
    for i in range(random.randint(0, 2)):
        key = 'secretleaf' + str(i)
        last[key] = 'sensitive-%d-%d' % (case, i)
        sensitive.append('/' + key)
        secrets.append(last[key])
    if sensitive and random.random() < 0.5:
        last['alias'] = '${config:' + sensitive[0] + '}'
        referenced.add(sensitive[0])
    request['sensitive'] = sensitive
    if random.random() < 0.3:
        request['sensitive_keys'] = random.sample(KEYS, 2)      # masks every path ending in those keys, aliases included
    constraints = []
    for path, value in random.sample(plain, min(len(plain), random.randint(0, 2))):
        kind = 'boolean' if isinstance(value, bool) else 'number' if isinstance(value, int) else 'string'
        constraint = {'path': path}
        roll = random.random()
        if roll < 0.4:
            constraint['type'] = kind
        elif roll < 0.6:
            constraint['type'] = random.choice([k for k in ['number', 'string', 'boolean'] if k != kind])
        elif kind == 'number':
            constraint['min'], constraint['max'] = random.randint(0, 500), random.randint(500, 999)
        elif kind == 'string' and random.random() < 0.5:
            constraint['pattern'] = random.choice(['^v[0-9]+$', '^[a-z]+$', '[0-9]', '^(v1|v2)$'])
        elif kind == 'string':
            constraint['min_length'], constraint['max_length'] = random.randint(1, 3), random.randint(2, 4)
        else:
            constraint['enum'] = [value] if random.random() < 0.5 else ['nope']
        constraints.append(constraint)
    for pointer in random.sample(sorted(set(array_paths(merged))), min(len(set(array_paths(merged))), random.randint(0, 1))):
        constraints.append({'path': pointer, 'type': 'array', 'min_length': random.randint(0, 2), 'max_length': random.randint(2, 5)})
    if random.random() < 0.3:
        constraints.append({'path': '/missing' + str(case), 'required': True})
    request['constraints'] = constraints
    return request, secrets, referenced


coverage = {'layers': 0, 'masked': 0, 'aliases': 0, 'references': 0, 'fallbacks': 0, 'shadowed': 0, 'key_masks': 0, 'issues': 0,
            'diffs': 0, 'replace': 0, 'append': 0, 'unique': 0, 'per_path': 0}


def check_case(case):
    request, secrets, referenced = build_case(case)
    oracle = Oracle(request)
    report, stdout = run(request)
    coverage['layers'] += len(request['layers'])
    coverage['masked'] += bool(oracle.masked)
    coverage['aliases'] += 'alias' in request['layers'][-1]['value']
    coverage['references'] += sum(k.startswith('ref') for k in request['layers'][-1]['value'])
    coverage['issues'] += bool(oracle.issues)
    coverage['fallbacks'] += sum(':-' in v for v in request['layers'][-1]['value'].values() if isinstance(v, str))
    coverage['shadowed'] += len(oracle.shadowed)
    coverage['key_masks'] += 'sensitive_keys' in request and bool(oracle.masked)
    if isinstance(request['arrays'], str):
        coverage[request['arrays']] += 1
    else:
        coverage['per_path'] += 1
    assert report['config'] == oracle.redacted and report['redacted'] == oracle.redacted, case
    assert report['masked'] == oracle.masked, case
    assert report['origins'] == oracle.origins, case
    assert report['shadowed'] == oracle.shadowed, case
    assert report['issues'] == oracle.issues and report['valid'] == (not oracle.issues), case
    export, export_out = run(dict(request, operation='export'))
    assert export['text'] == canonical(oracle.redacted), case
    if not (request.get('sensitive') or request.get('sensitive_keys') or request.get('secret_env')):
        inferred, _ = run(dict(request, operation='infer'))
        assert inferred['constraints'] == infer_constraints(request) and inferred['valid'] and inferred['issues'] == [], case
    flat, _ = run(dict(request, operation='export', format='flat'))
    assert flat['text'] == canonical(dict(flatten(oracle.redacted))), case
    dotenv_lines, collision = render_dotenv(oracle.redacted)
    if collision:
        assert fails(dict(request, operation='export', format='dotenv')), case
    else:
        dotenv, dotenv_out = run(dict(request, operation='export', format='dotenv'))
        assert dotenv['text'] == dotenv_lines, case
        for secret in secrets:
            assert secret not in dotenv_out, case
    shuffled, shuffled_out = run(shuffle_keys(request))
    assert canonical(shuffled['config']) == canonical(report['config']), case
    assert canonical(shuffled['origins']) == canonical(report['origins']), case
    assert run(shuffle_keys(dict(request, operation='export')))[0]['text'] == export['text'], case
    revealed, _ = run(dict(request, reveal=True))
    assert revealed['config'] == oracle.resolved, case
    for secret in secrets:
        assert secret not in stdout and secret not in export_out and secret not in shuffled_out, case
    # Diff: change one plain, unreferenced, unmasked leaf of the last layer.
    last = request['layers'][-1]['value']
    def visible(path):
        prefixes = [path[:i] for i, ch in enumerate(path) if ch == '/'] + [path]
        return not any(oracle.is_masked(prefix) for prefix in prefixes if prefix)
    candidates = [p for p, v in leaf_paths(last) if p not in referenced and visible(p)
                  and isinstance(v, int) and not isinstance(v, bool)]
    if candidates:
        coverage['diffs'] += 1
        path = random.choice(candidates)
        mutated = json.loads(json.dumps(request))
        parts = [part.replace('~1', '/').replace('~0', '~') for part in path.split('/')[1:]]
        node = mutated['layers'][-1]['value']
        for part in parts[:-1]:
            node = node[part]
        node[parts[-1]] = node[parts[-1]] + 1000
        diff, diff_out = run({'operation': 'diff', 'old': request, 'new': mutated})
        assert [c['path'] for c in diff['changes']] == [path] and diff['changes'][0]['type'] == 'changed', case
        ignored, _ = run({'operation': 'diff', 'old': request, 'new': mutated, 'ignore': [path.rsplit('/', 1)[0] or path]})
        assert ignored['equal'] and ignored['changes'] == [], case                      # ignoring the parent hides the change
        assert diff['changes'][0]['after'] == diff['changes'][0]['before'] + 1000, case
        assert diff['changes'][0]['after_origins'] == oracle.origins[path], case
        for secret in secrets:
            assert secret not in diff_out, case


def main():
    for case in range(100):
        check_case(case)
    print('Independent configuration oracle: 100 tenant configuration sets agree on merge, origins, shadowing, masking, constraints, export, key-order invariance and diff')
    print('Coverage:', ', '.join('%s=%d' % item for item in coverage.items()))

    # --- failure validation -----------------------------------------------------

    def layers(*values):
        return {'layers': [{'name': 'l' + str(i), 'value': v} for i, v in enumerate(values)]}

    assert fails(dict(layers({'a': '${config:/b}', 'b': '${config:/a}'})))                       # interpolation cycle
    assert fails(dict(layers({'a': '${env:NOPE}'})))                                              # missing environment variable
    assert fails(dict(layers({'x': 1}, {'x': 'one'}), strict_types=True))                        # type conflict
    assert fails(dict(layers({'x': [1]}, {'x': [2]}), arrays='concat'))                          # unknown array strategy
    deep_ok, deep_bad = {}, {}
    node_ok, node_bad = deep_ok, deep_bad
    for _ in range(100):
        node_ok = node_ok.setdefault('d', {})
    for _ in range(131):
        node_bad = node_bad.setdefault('d', {})
    node_ok['leaf'] = 1
    pointer = '/d' * 100 + '/leaf'
    report, _ = run(layers(deep_ok, json.loads(json.dumps(deep_ok))))
    assert at(report['config'], pointer) == 1 and report['origins'][pointer] == ['l0', 'l1']   # deep path traceable
    assert fails(layers(deep_bad, json.loads(json.dumps(deep_bad))))                             # nesting limit
    print('Failure validation: cycle, missing environment variable, type conflict, array strategy and deep path limits rejected')


if __name__ == '__main__':
    main()
