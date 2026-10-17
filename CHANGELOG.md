# Changelog

## Unreleased

- `arrays` accepts per-path JSON Pointer assignments in addition to a single global strategy (`{"default": "append", "unique": ["/matrix/targets"]}`); unassigned arrays keep the default.
- Merge reports list `shadowed` entries ({path, layer, by}) for every override that replaced a different value, pointing audits straight at the overriding layer; re-setting an identical value is not shadowing.
- References accept a literal fallback (`${env:NAME:-text}`, `${config:/pointer:-text}`) used only when the target is absent; an empty environment value is present and still wins.

## 1.0.0 — 2026-10-16

Registry version: not yet published. mooncakes.io requires `0.x.y` version numbers, so this release needs a zero-major registry number; `0.1.0` on the registry is the initial implementation.

Complete implementation of the proposed scope: the three scenarios run end to end, the acceptance checks are executable, and the release is verified against independent oracles.

### Engine

- Added `operation: "export"`: canonical JSON text (UTF-16 code-unit key order, no whitespace) of the resolved configuration, redacted unless `reveal` is set.
- Diff results now carry `before_origins`/`after_origins` per change and report `masked_override` entries when a hidden value's origin chain changed.
- Merge reports list `masked` (every redacted path) and echo per-layer `source` labels (the host adapter records the file name).
- Constraint verdicts report the first violated clause in a fixed order (type, enum, min, max); unknown constraint types are rejected.
- Unknown operations are rejected instead of being treated as merges; layer names, sensitive paths, duplicate layers and constraint types are validated explicitly.
- Error values print their bare message (`missing environment variable: X` instead of `InputError(...)`); messages still never contain values.
- Canonical ordering is now UTF-16 code unit order (`String::lexical_compare`) on every backend, instead of depending on the toolchain's length-first `Compare for String`.
- Trait promotions follow the moonbitlang/core policy via `extends.mbt`; the package builds with `--deny-warn` on the 2026-10 toolchain.

### Host adapter and tooling

- `scripts/files.py` labels layers with their source files and relays only the engine's structured, value-free error message on failure.
- `tests/cases.json` grew from 8 to 33 cases and is now the single source of truth; `scripts/fixtures.py` generates `fixtures_wbtest.mbt` and `docs/usage.md` from it (with `--check` for CI).
- New `scripts/reference.py`: an independent Python implementation of the documented semantics, compared with the engine over 100 generated environment/tenant configuration sets (merge, origins, masking, constraints, export, key-order invariance, diff) plus the failure paths.
- New `scripts/scenarios.py`: the three proposal scenarios through the host adapter, 38 checks.
- New `scripts/stats.py` (source statistics by category) and `scripts/consume.sh` (a fresh module consumes the published package from mooncakes.io).

### Scenarios

- `examples/service`, `examples/ci` and `examples/tenants` replace the three single-request samples with complete file-based scenarios (TOML + JSON layers, environment allowlists, secrets, constraints, strict-type conflicts, audits and exports), documented in `docs/scenarios.md`.

### CI

- `moon check --deny-warn` on all four backends, `moon fmt --check`, interface freshness (`moon info` diff), fixture freshness, the scenarios and the package consumption check on version tags.

## 0.1.0 — 2026-10-05

Initial implementation: layered merge with array strategies, interpolation with cycle detection, origins, redaction, constraints, redacted diff, JSON CLI, Python file adapter, 8 fixture cases, 20-case merge oracle, CI on four backends.
