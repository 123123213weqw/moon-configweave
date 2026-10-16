# Attribution

The domain code in this repository was implemented for this project with AI coding assistance. Shared JSON-value/CLI scaffolding is used across the October projects; it is infrastructure rather than nine independent domain algorithms.

## Design references

- [https://www.rfc-editor.org/rfc/rfc6901](https://www.rfc-editor.org/rfc/rfc6901) — JSON Pointer syntax used for paths, origins and references.
- [https://www.rfc-editor.org/rfc/rfc8785](https://www.rfc-editor.org/rfc/rfc8785) — key ordering (UTF-16 code units) adopted for canonical export.
- [https://docs.python.org/3/library/tomllib.html](https://docs.python.org/3/library/tomllib.html) — TOML parsing in the host adapter.
- [https://toml.io/en/v1.0.0](https://toml.io/en/v1.0.0) — TOML 1.0.0 as the format reference for layer files.

References inform formats and algorithms; they are not claims of interoperability with every feature of the referenced systems. MoonBit core is a toolchain dependency. Python standard-library and Node built-in APIs are used by host adapters, scenario runners and test oracles; no third-party packages are required. Scenario inputs under `examples/` and generated oracle data are synthetic. No prior September project implementation was copied into this domain core.
