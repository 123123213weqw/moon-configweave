# Implemented architecture

## Core

Recursive JSON object merges; replace/append/unique array modes; optional strict types; path provenance histories; environment/config interpolation preserving whole-reference types; cycle/depth detection; secret propagation across scalar and container aliases; redaction; required/type/enum/range constraints; redacted environment comparisons. scripts/files.py imports JSON and TOML with Python tomllib.

## Boundaries

Core input is JSON values; TOML is parsed by the optional Python 3.11+ host adapter. Secret fields and secret environment variable names must be designated explicitly. Default output is redacted; reveal=true explicitly returns plaintext. Origins record applied layer history, including replaced historical paths. Diff compares redacted values: changes between two hidden secret values cannot be detected from that report. No schema standard implementation. Arrays are compared as whole values. TOML date/time objects cannot be represented by the JSON adapter and are rejected.

## Integration

The core accepts semantic values and returns deterministic JSON-shaped reports. Host adapters handle files, network or processes; they invoke the compiled MoonBit engine. The CLI package declares `supported_targets = "js"`; other backends test the portable core.

## Validation evidence

Fixture cases are hand-checked assertions. Independent reference checks and integration scripts are runnable from a clean checkout. CI executes four core backends and host checks. Historical proposal targets are not release results.
