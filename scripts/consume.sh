#!/bin/sh
# Independent consumption check: a fresh module adds the published package from
# mooncakes.io, imports it like any other consumer, and runs a request through it.
#   sh scripts/consume.sh 0.1.0      # the registry version to verify
# Registry versions are zero-major (mooncakes.io policy) and are listed in CHANGELOG.md.
set -eu
version="${1:?usage: sh scripts/consume.sh REGISTRY_VERSION}"
package="123123213weqw/moon_configweave"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/consumer/cmd/main"
cd "$work/consumer"
printf 'name = "verify/consumer"\n\nversion = "0.1.0"\n' > moon.mod
printf 'import {\n  "%s" @engine,\n  "moonbitlang/core/json",\n}\n\npkgtype(kind: "executable")\n' "$package" > cmd/main/moon.pkg
cat > cmd/main/main.mbt <<'MBT'
///|
fn main {
  let request = @json.parse(
    "{\"layers\":[{\"name\":\"base\",\"value\":{\"db\":{\"host\":\"local\",\"port\":1}}},{\"name\":\"prod\",\"value\":{\"db\":{\"port\":2}}}]}",
  ) catch {
    _ => abort("request")
  }
  let report = @engine.execute(request) catch {
    _ => abort("engine")
  }
  println(report.stringify())
}
MBT
moon add "$package@$version"
moon update >/dev/null
output="$(moon run cmd/main --target js 2>/dev/null)"
case "$output" in
  *'"port":2'*'"origins":{'*'"/db/port":["base","prod"]'*) ;;
  *) echo "unexpected output: $output" >&2; exit 1 ;;
esac
echo "Independent consumption verified: $package@$version merged two layers from a fresh module (moon $(moon version | head -1 | cut -d' ' -f2))"
