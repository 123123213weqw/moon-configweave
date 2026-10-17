// Property-style tests that build their inputs programmatically; the
// example-driven cases live in fixtures_wbtest.mbt.

///|
fn nested(depth : Int32, leaf : Value) -> Value {
  let mut value = leaf
  for i = depth - 1; i >= 0; i = i - 1 {
    value = record([("k" + i.to_string(), value)])
  }
  value
}

///|
fn layer(name : String, value : Value) -> Value {
  record([("name", String(name)), ("value", value)])
}

///|
fn export_text(request : Value) -> String raise {
  str(get(run(request), "text"))
}

///|
test "key order never changes the merged configuration" {
  let forward = parse(
    "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1,\"y\":{\"p\":[1,2],\"q\":\"${config:/x}\"}}},{\"name\":\"b\",\"value\":{\"y\":{\"r\":true},\"z\":\"${env:E}\"}}],\"env\":{\"E\":\"e\"},\"arrays\":\"unique\"}",
  )
  let shuffled = parse(
    "{\"arrays\":\"unique\",\"env\":{\"E\":\"e\"},\"layers\":[{\"value\":{\"y\":{\"q\":\"${config:/x}\",\"p\":[1,2]},\"x\":1},\"name\":\"a\"},{\"value\":{\"z\":\"${env:E}\",\"y\":{\"r\":true}},\"name\":\"b\"}]}",
  )
  assert_eq(
    canonical(get(run(forward), "config")),
    canonical(get(run(shuffled), "config")),
  )
  assert_eq(
    canonical(get(run(forward), "origins")),
    canonical(get(run(shuffled), "origins")),
  )
  let export_forward = forward.to_json() |> from_json
  let export_shuffled = shuffled.to_json() |> from_json
  match (export_forward, export_shuffled) {
    (Object(a), Object(b)) => {
      a["operation"] = String("export")
      b["operation"] = String("export")
    }
    _ => abort("fixtures are objects")
  }
  assert_eq(export_text(export_forward), export_text(export_shuffled))
}

///|
test "deep configuration stays traceable up to the nesting limit" {
  let depth = 100
  let request = record([
    (
      "layers",
      Array([
        layer("base", nested(depth, Number(1.0))),
        layer("deep", nested(depth, Number(2.0))),
      ]),
    ),
  ])
  let result = run(request)
  let mut pointer = ""
  for i = 0; i < depth; i = i + 1 {
    pointer += "/k" + i.to_string()
  }
  assert_eq(at(get(result, "config"), pointer), Number(2.0))
  assert_eq(get(get(result, "origins"), pointer), strings(["base", "deep"]))
}

///|
test "nesting beyond the limit is rejected" {
  let request = record([
    (
      "layers",
      Array([
        layer("base", nested(130, Number(1.0))),
        layer("deep", nested(130, Number(2.0))),
      ]),
    ),
  ])
  let failed = try {
    ignore(run(request))
    false
  } catch {
    InputError(message) => message == "configuration nesting limit"
    _ => false
  }
  assert_true(failed)
}

///|
test "interpolation chains resolve in dependency order" {
  let fields : Map[String, Value] = Map([])
  fields["v0"] = Number(7.0)
  for i = 1; i <= 40; i = i + 1 {
    // Joined rather than concatenated: the JS backend fuses `"${" + x` into
    // an unescaped template literal.
    fields["v" + i.to_string()] = String(
      ["${config:/v", (i - 1).to_string(), "}"].join(""),
    )
  }
  let result = run(
    record([("layers", Array([layer("chain", Object(fields))]))]),
  )
  assert_eq(get(get(result, "config"), "v40"), Number(7.0))
}

///|
test "error messages never contain configuration values" {
  let request = parse(
    "{\"layers\":[{\"name\":\"x\",\"value\":{\"token\":\"${env:TOKEN}\",\"copy\":\"${config:/token}\",\"broken\":\"${config:/token/0}\"}}],\"env\":{\"TOKEN\":\"hunter2\"},\"secret_env\":[\"TOKEN\"]}",
  )
  let message = try {
    ignore(run(request))
    ""
  } catch {
    error => error.to_string()
  }
  assert_true(message != "")
  assert_false(message.contains("hunter2"))
}

///|
test "flatten and pointer helpers" {
  let value = parse(
    "{\"a\":{\"b\":[1,{\"c\":true}],\"x/y\":\"slash\",\"empty\":{}},\"n\":null}",
  )
  let flat = value.flatten()
  assert_eq(flat["/a/b/0"], Number(1.0))
  assert_eq(flat["/a/b/1/c"], Bool(true))
  assert_eq(flat["/a/x~1y"], String("slash"))
  assert_eq(flat["/a/empty"], Object(Map([])))
  assert_eq(flat["/n"], Null)
  assert_eq(flat.length(), 5)
  assert_eq(value.pointer("/a/x~1y"), String("slash"))
  assert_eq(value.pointer("/a/b/1"), parse("{\"c\":true}"))
  assert_eq(value.pointer(""), value)
  let missing = try {
    ignore(value.pointer("/a/nope"))
    false
  } catch {
    InputError(message) => message.has_prefix("missing configuration reference")
    _ => false
  }
  assert_true(missing)
  assert_eq(
    value.canonical(),
    "{\"a\":{\"b\":[1,{\"c\":true}],\"empty\":{},\"x/y\":\"slash\"},\"n\":null}",
  )
  assert_eq(parse("{\"b\":1,\"a\":2}").canonical(), "{\"a\":2,\"b\":1}")
}
