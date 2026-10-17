# Moon ConfigWeave

Layered configuration audit, implemented in MoonBit with a JSON CLI and reusable library API: merge configuration layers, resolve references, trace every value to the layer and file that set it, mask secrets, validate constraints, compare environments and export a canonical artifact.

- Repository: [https://github.com/123123213weqw/moon-configweave](https://github.com/123123213weqw/moon-configweave)
- Package: `123123213weqw/moon_configweave` on mooncakes.io (registry versions are listed in CHANGELOG.md)
- License: Apache-2.0
- Release scope: **1.0.0 complete implementation** of the scope defined in `docs/proposal.md`. The three proposed scenarios run end to end, the acceptance checks (100 reference-validated configuration sets, key-order invariance, masking, failure paths) are executable, and the remaining limits are listed in [docs/boundaries.md](docs/boundaries.md). See [CHANGELOG.md](CHANGELOG.md) for what changed since 0.1.0.

## Implemented

- **Layer merge**: recursive object merge in layer order with `replace` (default), `append` or `unique` array strategies, assignable per request or per JSON Pointer path; optional `strict_types` rejects type-changing overlays; nesting is limited to 128 levels.
- **Provenance**: `origins` maps every JSON Pointer path to the ordered list of layers that contributed to it, `shadowed` names the layer each override replaced, and each layer may carry a `source` label (the host adapter uses the file name) echoed in the report.
- **Interpolation**: `${env:NAME}` and `${config:/json/pointer}` references with optional `:-literal` fallbacks for absent targets; a whole-string reference keeps the referenced type, embedded references render scalars; cycles, missing references and depth limits are rejected.
- **Secrets**: `sensitive` paths and `secret_env` names are redacted to `***`, and secrecy propagates through scalar and container aliases; `masked` lists every redacted path; output is redacted unless `reveal` is true.
- **Constraints**: `required`, `type`, `enum`, `pattern` (unanchored regex search), `min_length`/`max_length` (strings and arrays), `min`, `max` per path; the first violated clause is reported in a fixed order; unknown types, clauses and invalid patterns are rejected.
- **Diff** (`operation: "diff"`): compares two redacted configurations, annotates each change with the origins on both sides, and reports a `masked_override` when a hidden value's origin chain changed without revealing it.
- **Export** (`operation: "export"`): canonical JSON text (keys in UTF-16 code unit order, no whitespace) for stable artifacts and hashing.
- **Host adapter**: `scripts/files.py` reads JSON and TOML layer files (Python 3.11+ `tomllib`) and copies allow-listed environment variables; the engine never reads files itself.

## Build and run

Use MoonBit and Node.js 24. The core library supports JS, wasm, wasm-gc and native; the filesystem/process CLI is JS only.

```sh
moon update
moon build --target js
moon run cmd/main --target js -- examples/request.json        # a self-contained request
node _build/js/debug/build/cmd/main/main.js examples/request.json
python -B scripts/files.py examples/service/dev.manifest.json  # layer files + environment via the adapter
```

Pass `-` to read a UTF-8 JSON request from stdin. A single request must be at most 16 MiB. The CLI prints one JSON result and exits 0 for a valid report, 2 for a report whose constraints found issues (`valid: false`), and 1 after printing `{"error": "..."}` for a rejected request. The host adapter uses the same codes. Error messages name paths and variable names, never values.

## Library use

mooncakes.io currently accepts only zero-major versions (`moon publish` rejects anything else with "In this very early stage, the major version must be '0'"), so repository releases and registry versions are numbered separately. The registry version corresponding to each repository release is recorded in [CHANGELOG.md](CHANGELOG.md); `0.1.0` is the initial implementation.

```sh
moon add 123123213weqw/moon_configweave@REGISTRY_VERSION
```

In the consumer's `moon.pkg`:

```moonbit
import {
  "123123213weqw/moon_configweave" @engine,
  "moonbitlang/core/json",
}
```

```moonbit
fn example(request : Json) -> Json raise {
  @engine.execute(request)
}
```

`execute(Json) -> Json raise` is the standard JSON boundary. `parse(StringView) -> Value raise`, `from_json(Json) -> Value`, `Value::to_json` and `run(Value) -> Value raise` provide a typed semantic value interface, and `Value::flatten` (leaf values by JSON Pointer), `Value::pointer` (lookup by JSON Pointer) and `Value::canonical` (canonical JSON text) help consumers work with reports. Object key order in requests is not significant; numeric values are finite doubles. The public interface is listed in `pkg.generated.mbti`.

## Requests and results

A merge request has `layers` (each `{name, value, source?}`), and optionally `arrays` (a strategy name or a per-path map), `strict_types`, `env`, `secret_env`, `sensitive`, `constraints` and `reveal`. The result has `config`, `redacted`, `masked`, `shadowed`, `origins`, `layers`, `issues` and `valid`. `operation: "diff"` takes `old` and `new` requests; `operation: "export"` takes a merge request and returns `text`. Every documented case in [docs/usage.md](docs/usage.md) is an executable fixture.

## Scenarios

The three scenarios from the proposal live in `examples/` as real input files with manifests, and `scripts/scenarios.py` runs all of them and checks their documented outcomes:

| Scenario | Inputs | What the output shows |
| --- | --- | --- |
| `examples/service` | TOML defaults, dev/prod JSON overrides, a database password from the environment | deployable dev config; a wrong `"5432"` string override in prod located at `/database/port` with origins `defaults → prod`; a dev/prod diff |
| `examples/ci` | base job plus linux/macos/windows overlays | `append` vs `unique` step and target merges; a Windows type conflict rejected under `strict_types` or reported as an issue; a stable single-line export |
| `examples/tenants` | app defaults, organization TOML policy, two tenant overrides | three-level resolution; tenant-b's rate limit and auth downgrade flagged; its hardcoded signing key reported as a `masked_override` without revealing it |

See [docs/scenarios.md](docs/scenarios.md) for the inputs, decision process and verifiable outputs of each scenario.

## Tests and verification

```sh
moon check --deny-warn --target js      # zero warnings on every backend
moon test --target js                   # 38 tests: 33 fixture cases + property tests
moon test --target wasm
moon test --target wasm-gc
moon test --target native               # requires a C compiler
moon build --target js
node scripts/check.mjs                  # the 33 fixtures through the real CLI
python -B scripts/reference.py          # 100 configuration sets vs an independent Python oracle
python -B scripts/integration.py        # TOML/JSON files, environment allowlist, adapter errors
python -B scripts/scenarios.py          # the three scenarios, 38 checks
python -B scripts/fixtures.py --check   # generated tests and usage guide match tests/cases.json
python -B scripts/stats.py              # source statistics by category
sh scripts/consume.sh REGISTRY_VERSION  # fresh module consumes the published package
```

`tests/cases.json` is the single source of the 33 fixture cases; `scripts/fixtures.py` generates `fixtures_wbtest.mbt` and `docs/usage.md` from it. The oracle in `scripts/reference.py` is a separate Python implementation of the documented semantics; it checks merged values (global and per-path array strategies), origins, shadowed overrides, fallback references, masked paths, constraint verdicts, export text, key-order invariance, diff output and secret masking over 100 generated environment/tenant configuration sets whose keys include unicode and RFC 6901 escapes, then the failure paths (cycle, missing variable, type conflict, array strategy, deep paths). Fixtures and scenario data are synthetic and are not presented as production adoption evidence. CI runs all of the above on every push; the consumption check runs on demand against a registry version.

## Current boundaries

Core input is JSON values; TOML is parsed by the optional Python 3.11+ host adapter. Secret fields and secret environment variable names must be designated explicitly. Default output is redacted; `reveal=true` explicitly returns plaintext. Diff compares redacted values: a change between two hidden secrets is only visible when its origin chain changed. Per-path array strategies match exact pointers only. There is no schema standard implementation, no escape sequence for a literal `${`, and no remote configuration source. TOML date/time values cannot be represented by the JSON adapter and are rejected. See [docs/boundaries.md](docs/boundaries.md).

See [source and dependency attribution](THIRD_PARTY.md). This release does not establish competition eligibility or organizer acceptance.
