# Implemented architecture (1.0.0)

## Pipeline

Every request passes through the same deterministic stages inside the MoonBit core:

1. **Validate** the request shape: operation, array strategy, layer names (unique), layer values (objects), sensitive paths (JSON Pointers), constraint types.
2. **Merge** layers in order. Objects merge key by key; arrays follow the strategy assigned to their exact path or the request default (`replace`, `append`, `unique`); scalars replace. With `strict_types`, an overlay that changes the kind of a non-null value is rejected. Each visited path records the contributing layer in `origins`, so a leaf's history is the ordered chain of layers that set it, and replaced subtrees keep the history of their historical paths. Every replacement of a different value is also recorded in `shadowed` as (path, overridden layer, overriding layer).
3. **Resolve** references. Strings are scanned for `${env:NAME}` and `${config:/pointer}`, optionally with a `:-literal` fallback used only when the target is absent; a whole-string reference yields the referenced value with its type, embedded references render scalars into text. Resolution is memoized per path, detects cycles through a visiting set, and bounds depth at 128.
4. **Taint**. Reading a secret environment variable, or a configuration path that is sensitive (by path or key name), actually contains a sensitive path, or is tainted, taints the reading path. This is what makes container aliases of secrets redact as a whole.
5. **Check constraints** against the resolved tree: `required`, then `type`, `enum`, `pattern`, `min_length`, `max_length`, `min`, `max` in that order; the first violated clause of each constraint becomes an issue. Clause names are validated up front.
6. **Redact** sensitive and tainted paths to `***`, collecting `masked` in code-unit order.
7. **Report**: `config` (redacted unless `reveal`), `redacted`, `masked`, `shadowed`, `origins`, `layers` (names and optional `source` labels), `issues`, `valid`.

`operation: "diff"` runs the pipeline on `old` and `new`, walks both redacted trees in sorted key order, annotates each change with the origins recorded on each side, emits `masked_override` entries for hidden values whose origin chains differ, and finally drops every entry at or below an `ignore` pointer. `operation: "export"` runs the pipeline and serializes the (redacted or revealed) configuration as canonical JSON text, as a flat pointer-to-leaf object, or as dotenv lines (keys derived from pointers — segments upper-cased, non-alphanumerics replaced by `_` — with collisions rejected; values bare when safe, JSON-quoted otherwise).

## Determinism

Object key order in requests never affects results: merges are keyed, origins are keyed by path, diff walks keys in UTF-16 code unit order, and export sorts keys the same way. The toolchain's `Compare for String` orders by length first; the engine therefore sorts keys explicitly with `String::lexical_compare` so canonical output matches RFC 8785 and ordinary JSON tooling. Numbers are finite doubles rendered by the JSON printer.

## Integration

The core accepts semantic values and returns JSON-shaped reports; it does not touch files, the network or processes. `scripts/files.py` is the host adapter: it loads `.json`/`.toml` layer files from the manifest directory, labels each layer with its file name, copies allow-listed environment variables, calls the compiled JS CLI over stdin, and relays only the engine's value-free error message on failure. The CLI package declares `supported_targets = "js"`; the other backends run the portable core and its tests.

## Public interface

`execute(Json) -> Json raise`, `run(Value) -> Value raise`, `parse(StringView) -> Value raise`, `from_json`, `Value::to_json`, `Value::stringify`, `Value::flatten`, `Value::pointer`, `Value::canonical`, `Value`, `InputError`. Trait promotions follow the moonbitlang/core policy (`extends.mbt`): `equal` and `to_string` are regular methods, derivatives go through the trait. The interface is recorded in `pkg.generated.mbti` and checked in CI.

## Validation evidence

- 33 fixture cases in `tests/cases.json`, run as generated MoonBit white-box tests on JS, wasm, wasm-gc and native, and through the real CLI by `scripts/check.mjs`.
- Property tests in `engine_wbtest.mbt`: key-order invariance, 100-level nesting, the nesting limit, 40-step interpolation chains, value-free error messages.
- `scripts/reference.py`: an independent Python implementation of the documented semantics compared with the engine over 100 generated environment/tenant configuration sets (merge with global and per-path array strategies, origins, shadowed overrides, fallback references, masked paths, constraints, export text, key-order invariance, diff, secret masking; keys include unicode and RFC 6901 escapes) plus the failure paths.
- `scripts/scenarios.py`: the three proposal scenarios executed through the host adapter with 38 checks.
- `scripts/integration.py`: real TOML/JSON loading, environment allowlist, redaction, source labels and adapter error handling.
- CI runs `moon check --deny-warn`, `moon fmt --check`, interface and fixture freshness checks, all of the above, and the package consumption check on demand against a registry version.

Historical proposal estimates (for example source line counts) are not release results; `scripts/stats.py` reports the actual numbers.
