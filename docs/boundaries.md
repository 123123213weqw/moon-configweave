# Current boundaries

- Core input is JSON values. TOML is parsed by the optional Python 3.11+ host adapter (`scripts/files.py`); TOML date/time values cannot be represented by the JSON adapter and are rejected.
- Secret fields and secret environment variable names must be designated explicitly (`sensitive`, `secret_env`). Anything not designated is treated as ordinary data.
- Default output is redacted; `reveal=true` explicitly returns plaintext in `config` and in `export` text. The redacted report is always included alongside.
- Diff compares redacted values. A change between two hidden secrets is invisible as a value change; it is reported as a `masked_override` only when the origin chains differ.
- Origins record applied layer history, including replaced historical paths, and `shadowed` records which layer each override replaced. Both name layers (and optional source labels); neither retains the historical values themselves.
- Array merge strategies (`replace`, `append`, `unique`) apply per request by default and can be assigned per exact JSON Pointer path; there is no prefix or wildcard matching, and elements inside arrays are compared as whole values.
- Constraints are fixed to `required`, `type`, `enum`, `min` and `max`; there is no expression language and no schema standard implementation. Constraint checking reports the first violated clause per constraint.
- Interpolation supports `${env:NAME}` and `${config:/json/pointer}`, each optionally with a `:-literal` fallback that applies only when the target is absent. There is no escape sequence for a literal `${`, no expression evaluation, no formatting of embedded structured values (a whole-string reference is the way to copy a container), and no remote configuration source.
- Nesting is limited to 128 levels and interpolation depth to 128. A single CLI request is limited to 16 MiB of UTF-8 input.
- Canonical key order is UTF-16 code unit order, which differs from code point order for supplementary-plane characters.
- Numeric values are finite doubles; the JSON adapter rejects NaN and infinity.
