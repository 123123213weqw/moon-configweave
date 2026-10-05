# Moon ConfigWeave

Layered configuration audit, implemented in MoonBit with a JSON CLI and reusable library API.

- Repository: [https://github.com/123123213weqw/moon-configweave](https://github.com/123123213weqw/moon-configweave)
- Package: `123123213weqw/moon_configweave@0.1.0`
- License: Apache-2.0
- Release scope: **0.1.0 initial implementation**. The broader competition proposal in `docs/proposal.md` is a reference design, not a claim that every planned capability is implemented.

## Implemented

Recursive JSON object merges; replace/append/unique array modes; optional strict types; path provenance histories; environment/config interpolation preserving whole-reference types; cycle/depth detection; secret propagation across scalar and container aliases; redaction; required/type/enum/range constraints; redacted environment comparisons. scripts/files.py imports JSON and TOML with Python tomllib.

## Build and run

Use MoonBit and Node.js 24. The core library supports JS, wasm, wasm-gc and native; the filesystem/HTTP/process CLI is JS only.

```sh
moon update
moon build --target js
moon run cmd/main --target js -- examples/scenario-1.json
node _build/js/debug/build/cmd/main/main.js examples/scenario-1.json
```

Pass `-` to read a UTF-8 JSON request from stdin. A single request must be at most 16 MiB. Successful requests print one JSON result; invalid requests exit nonzero. The host runner is a separate process and does not edit the input request file.

## Library use

```sh
moon add 123123213weqw/moon_configweave@0.1.0
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

`execute(Json) -> Json raise` is the standard JSON boundary. `from_json`, `Value::to_json`, and `run(Value) -> Value raise` provide a typed semantic value interface. Object ordering is not significant; numeric values use finite Double. Public domain functions are listed in `pkg.generated.mbti`.

## Tests

```sh
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native  # requires a C compiler
moon build --target js
node scripts/check.mjs
python -B scripts/reference.py
```

There are 8 checked fixture cases in `tests/cases.json`, executed both in MoonBit white-box tests and through the actual Node CLI. Independent reference checks use Python's standard library or separately written algorithms. Fixtures are synthetic and are not presented as production adoption evidence. See [input and output examples](docs/usage.md) and [current boundaries](docs/boundaries.md).

## Current boundaries

Core input is JSON values; TOML is parsed by the optional Python 3.11+ host adapter. Secret fields and secret environment variable names must be designated explicitly. Default output is redacted; reveal=true explicitly returns plaintext. Origins record applied layer history, including replaced historical paths. Diff compares redacted values: changes between two hidden secret values cannot be detected from that report. No schema standard implementation. Arrays are compared as whole values. TOML date/time objects cannot be represented by the JSON adapter and are rejected.

See [source and dependency attribution](THIRD_PARTY.md). This release does not establish competition eligibility or organizer acceptance.
