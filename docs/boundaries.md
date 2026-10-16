# Version 1.0.0 boundaries

- Core input is JSON values. TOML is parsed by the optional Python 3.11+ host adapter (`scripts/files.py`); TOML date/time values cannot be represented by the JSON adapter and are rejected.
- Secret fields and secret environment variable names must be designated explicitly (`sensitive`, `secret_env`). Anything not designated is treated as ordinary data.
- Default output is redacted; `reveal=true` explicitly returns plaintext in `config` and in `export` text. The redacted report is always included alongside.
- Diff compares redacted values. A change between two hidden secrets is invisible as a value change; it is reported as a `masked_override` only when the origin chains differ.
- Origins record applied layer history, including replaced historical paths. They name layers (and optional source labels); they do not retain the historical values themselves.
- The array merge strategy is global per request (`replace`, `append`, `unique`). There is no per-path strategy override.
- Constraints are fixed to `required`, `type`, `enum`, `min` and `max`; there is no expression language and no schema standard implementation. Constraint checking reports the first violated clause per constraint.
- Interpolation supports `${env:NAME}` and `${config:/json/pointer}` only. There is no escape sequence for a literal `${`, no default values, no formatting of embedded structured values (a whole-string reference is the way to copy a container), and no remote configuration source.
- Nesting is limited to 128 levels and interpolation depth to 128. A single CLI request is limited to 16 MiB of UTF-8 input.
- Canonical key order is UTF-16 code unit order, which differs from code point order for supplementary-plane characters.
- Numeric values are finite doubles; the JSON adapter rejects NaN and infinity.
