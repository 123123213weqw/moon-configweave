# The three complete scenarios

Each scenario is a directory of real input files plus manifests under `examples/`, executed by `python -B scripts/scenarios.py`, which runs every manifest through the host adapter and checks the documented outcomes (38 checks in total). The scenario data is synthetic. To run one by hand, set the synthetic secrets and call the adapter:

```sh
export ORDERS_DB_PASSWORD=dev-pw PORTAL_CLIENT_SECRET=portal ACME_WEBHOOK_KEY=webhook
python -B scripts/files.py examples/service/dev.manifest.json
python -B scripts/files.py examples/service/prod.manifest.json        # exit 1: report is invalid
python -B scripts/files.py examples/service/diff.manifest.json
```

## 1. Service environment configuration (`examples/service`)

**Inputs.** `defaults.toml` (service, database, cache sections; the database password is `${env:ORDERS_DB_PASSWORD}` and the URL interpolates four other paths), `dev.json` (log level, features, dev host, cache on) and `prod.json` (port 443, 8 workers, prod host, and a wrong override: the port as the string `"5432"`). Each manifest allows only `ORDERS_DB_PASSWORD` from the environment and declares it secret; constraints bound the ports, workers and log level.

**Process.** The adapter loads the TOML/JSON files inside the manifest directory, labels the layers with their file names, and the engine merges (unique arrays), resolves the URL through the referenced paths, redacts the password and checks the constraints.

**Verifiable outputs.** The dev report is valid, `features` is `["metrics","debugger"]`, the URL is `postgres://orders@db.dev.internal:5432/orders`, and `/database/password` is masked. The prod report exits 1 with the single issue `{"path": "/database/port", "reason": "type mismatch"}` whose origins are `["defaults", "prod"]` — the wrong override is located. The diff lists every environment difference with origins on both sides, except under `/cache`, which the manifest ignores; `/database/url` changes although no layer touched it directly, because its reference changed; the password never appears.

## 2. CI multi-platform configuration (`examples/ci`)

**Inputs.** `base.json` (runner, timeout, steps, `MOON_HOME` interpolated from `paths.home`, target matrix) and `linux.json`, `macos.json`, `windows.json` overlays. `windows.json` sets `timeout_minutes` to the string `"60"`.

**Process.** `linux.manifest.json` uses `append` (steps accumulate, and the duplicated `wasm-gc` target becomes visible), `macos.manifest.json` uses `unique` (the duplicate disappears), and `export-linux.manifest.json` exports the linux job as canonical text. `windows-strict.manifest.json` turns on `strict_types`; `windows-report.manifest.json` keeps it off.

**Verifiable outputs.** Linux and macOS merge cleanly with platform-correct `MOON_HOME` values. Under `strict_types` the Windows run fails with exactly `type-changing overlay at /job/timeout_minutes`; without it, the same conflict is reported as an issue attributed to `windows.json`. The export is a single line whose text equals the independently computed canonical JSON of the redacted configuration.

## 3. Multi-tenant configuration audit (`examples/tenants`)

**Inputs.** `defaults.json` (app defaults, a client secret from the environment), `org-acme.toml` (organization policy: locale, rate limit, OIDC provider and issuer, a webhook key from the environment) and two tenants: `tenant-a.json` (storage quota, shorter sessions) and `tenant-b.json` (a rate limit of 100000, auth downgraded back to `builtin`, and a hardcoded webhook signing key). The secrets are designated by key name (`sensitive_keys: ["client_secret", "signing_key"]`), so they are masked wherever they appear; constraints cap the rate limit at 10000, require the OIDC issuer, and restrict the provider enum.

**Process.** Each tenant manifest resolves defaults → organization → tenant. The audit manifest diffs tenant-a against tenant-b.

**Verifiable outputs.** Tenant-a is valid and fully masked (`/auth/client_secret`, `/integrations/webhook/signing_key`). Tenant-b exits 1 with `above maximum` and `not in enum`, both attributed to `tenant-b.json` through their origin chains. The audit diff lists the visible differences with origins, and reports the signing key as a `masked_override` with before/after origins — the tenant-level override of a secret is located without either value being printed. No secret value appears in any report or error message.
