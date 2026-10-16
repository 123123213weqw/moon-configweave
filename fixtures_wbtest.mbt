// Generated from tests/cases.json by scripts/fixtures.py; do not edit.

///|
fn test_at(value : Value, parts : Array[String]) -> Value raise {
  let mut current = value
  for part in parts {
    current = match current {
      Object(fields) =>
        match fields.get(part) {
          Some(v) => v
          None => raise InputError("test key missing: " + part)
        }
      Array(items) => items[num(parse(part)).to_int()]
      _ => raise InputError("invalid test traversal")
    }
  }
  current
}

///|
fn fails(request : String) -> Bool {
  try {
    ignore(run(parse(request)))
    false
  } catch {
    _ => true
  }
}

///|
test "layer merge" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"base\",\"value\":{\"db\":{\"host\":\"local\",\"port\":1}}},{\"name\":\"prod\",\"value\":{\"db\":{\"port\":2}}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "db", "host"]), parse("\"local\""))
  assert_eq(test_at(result, ["config", "db", "port"]), parse("2"))
  assert_eq(
    test_at(result, ["origins", "/db/port"]),
    parse("[\"base\",\"prod\"]"),
  )
}

///|
test "interpolation keeps type" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"n\":3,\"copy\":\"${config:/n}\",\"message\":\"n=${config:/n}\"}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "copy"]), parse("3"))
  assert_eq(test_at(result, ["config", "message"]), parse("\"n=3\""))
}

///|
test "secret aliases" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"db\":{\"password\":\"${env:KEY}\"},\"alias\":\"${config:/db}\"}}],\"env\":{\"KEY\":\"secret\"},\"secret_env\":[\"KEY\"]}",
    ),
  )
  assert_eq(test_at(result, ["config", "db", "password"]), parse("\"***\""))
  assert_eq(test_at(result, ["config", "alias"]), parse("\"***\""))
  assert_eq(test_at(result, ["masked"]), parse("[\"/alias\",\"/db/password\"]"))
}

///|
test "unique arrays" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[1,2]}},{\"name\":\"b\",\"value\":{\"x\":[2,3]}}],\"arrays\":\"unique\"}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse("[1,2,3]"))
}

///|
test "replace arrays by default" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[1,2]}},{\"name\":\"b\",\"value\":{\"x\":[3]}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse("[3]"))
  assert_eq(test_at(result, ["origins", "/x"]), parse("[\"a\",\"b\"]"))
}

///|
test "append arrays" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[1,2]}},{\"name\":\"b\",\"value\":{\"x\":[2,3]}}],\"arrays\":\"append\"}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse("[1,2,2,3]"))
  assert_eq(test_at(result, ["origins", "/x/2"]), parse("[\"b\"]"))
}

///|
test "unknown array strategy" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[1]}}],\"arrays\":\"merge\"}",
    ),
  )
}

///|
test "deep path merge" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"base\",\"value\":{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":{\"f\":{\"g\":{\"h\":{\"i\":{\"j\":{\"k\":{\"l\":1}}}}}}}}}}}}},{\"name\":\"deep\",\"value\":{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":{\"f\":{\"g\":{\"h\":{\"i\":{\"j\":{\"k\":{\"l\":2}}}}}}}}}}}}}]}",
    ),
  )
  assert_eq(
    test_at(result, [
      "config", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
    ]),
    parse("2"),
  )
  assert_eq(
    test_at(result, ["origins", "/a/b/c/d/e/f/g/h/i/j/k/l"]),
    parse("[\"base\",\"deep\"]"),
  )
}

///|
test "non-strict scalar replaces object" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":{\"y\":1}}},{\"name\":\"b\",\"value\":{\"x\":5}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse("5"))
  assert_eq(test_at(result, ["origins", "/x"]), parse("[\"a\",\"b\"]"))
}

///|
test "strict types allow null base" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":null}},{\"name\":\"b\",\"value\":{\"x\":1}}],\"strict_types\":true}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse("1"))
}

///|
test "missing env" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":\"${env:MISSING}\"}}]}",
    ),
  )
}

///|
test "cycle" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":\"${config:/b}\",\"b\":\"${config:/a}\"}}]}",
    ),
  )
}

///|
test "type conflict" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}},{\"name\":\"b\",\"value\":{\"x\":\"a\"}}],\"strict_types\":true}",
    ),
  )
}

///|
test "embedded structured reference" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"obj\":{\"k\":1},\"text\":\"v=${config:/obj}\"}}]}",
    ),
  )
}

///|
test "unterminated interpolation" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":\"${env:HOME\"}}],\"env\":{\"HOME\":\"h\"}}",
    ),
  )
}

///|
test "non-pointer config reference" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":1,\"b\":\"${config:a}\"}}]}",
    ),
  )
}

///|
test "missing config reference" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"b\":\"${config:/nope}\"}}]}",
    ),
  )
}

///|
test "embedded env and config references" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"port\":5,\"url\":\"host=${env:HOST}:${config:/port}\"}}],\"env\":{\"HOST\":\"h\"}}",
    ),
  )
  assert_eq(test_at(result, ["config", "url"]), parse("\"host=h:5\""))
}

///|
test "sensitive path with reveal" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"db\":{\"password\":\"plain\",\"host\":\"h\"}}}],\"sensitive\":[\"/db/password\"],\"reveal\":true}",
    ),
  )
  assert_eq(test_at(result, ["config", "db", "password"]), parse("\"plain\""))
  assert_eq(test_at(result, ["redacted", "db", "password"]), parse("\"***\""))
  assert_eq(test_at(result, ["redacted", "db", "host"]), parse("\"h\""))
}

///|
test "numeric constraint wrong type" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":\"text\"}}],\"constraints\":[{\"path\":\"/x\",\"min\":1}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse("false"))
  assert_eq(
    test_at(result, ["issues", "0", "reason"]),
    parse("\"numeric minimum requires number\""),
  )
}

///|
test "constraint first failure" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":\"text\"}}],\"constraints\":[{\"path\":\"/x\",\"type\":\"number\",\"min\":1}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse("false"))
  assert_eq(test_at(result, ["issues", "0", "path"]), parse("\"/x\""))
  assert_eq(
    test_at(result, ["issues", "0", "reason"]),
    parse("\"type mismatch\""),
  )
}

///|
test "required missing" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}}],\"constraints\":[{\"path\":\"/missing\",\"required\":true},{\"path\":\"/also-missing\"}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse("false"))
  assert_eq(test_at(result, ["issues", "0", "path"]), parse("\"/missing\""))
  assert_eq(
    test_at(result, ["issues", "0", "reason"]),
    parse("\"required value missing\""),
  )
}

///|
test "constraints satisfied" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"mode\":\"fast\",\"workers\":4}}],\"constraints\":[{\"path\":\"/mode\",\"type\":\"string\",\"enum\":[\"fast\",\"safe\"]},{\"path\":\"/workers\",\"type\":\"number\",\"min\":1,\"max\":64}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse("true"))
  assert_eq(test_at(result, ["issues"]), parse("[]"))
}

///|
test "unknown constraint type" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}}],\"constraints\":[{\"path\":\"/x\",\"type\":\"integer\"}]}",
    ),
  )
}

///|
test "layer sources" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"defaults\",\"value\":{\"a\":1},\"source\":\"defaults.toml\"},{\"name\":\"prod\",\"value\":{\"a\":2},\"source\":\"prod.json\"}]}",
    ),
  )
  assert_eq(test_at(result, ["layers", "0", "name"]), parse("\"defaults\""))
  assert_eq(
    test_at(result, ["layers", "0", "source"]),
    parse("\"defaults.toml\""),
  )
  assert_eq(test_at(result, ["layers", "1", "source"]), parse("\"prod.json\""))
  assert_eq(test_at(result, ["config", "a"]), parse("2"))
}

///|
test "duplicate layer name" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}},{\"name\":\"a\",\"value\":{\"x\":2}}]}",
    ),
  )
}

///|
test "export canonical text" {
  let result = run(
    parse(
      "{\"operation\":\"export\",\"layers\":[{\"name\":\"b\",\"value\":{\"z\":1,\"a\":{\"y\":[2,1],\"x\":\"${config:/z}\"}}},{\"name\":\"o\",\"value\":{\"a\":{\"w\":true}}}]}",
    ),
  )
  assert_eq(
    test_at(result, ["text"]),
    parse(
      "\"{\\\"a\\\":{\\\"w\\\":true,\\\"x\\\":1,\\\"y\\\":[2,1]},\\\"z\\\":1}\"",
    ),
  )
  assert_eq(test_at(result, ["redacted"]), parse("true"))
  assert_eq(test_at(result, ["valid"]), parse("true"))
}

///|
test "export hides secrets unless revealed" {
  let result = run(
    parse(
      "{\"operation\":\"export\",\"layers\":[{\"name\":\"x\",\"value\":{\"token\":\"${env:T}\"}}],\"env\":{\"T\":\"s3cret\"},\"secret_env\":[\"T\"]}",
    ),
  )
  assert_eq(test_at(result, ["text"]), parse("\"{\\\"token\\\":\\\"***\\\"}\""))
  assert_eq(test_at(result, ["redacted"]), parse("true"))
}

///|
test "export orders keys by code unit" {
  let result = run(
    parse(
      "{\"operation\":\"export\",\"layers\":[{\"name\":\"x\",\"value\":{\"db\":1,\"cache\":2,\"10\":3,\"9\":4}}]}",
    ),
  )
  assert_eq(
    test_at(result, ["text"]),
    parse("\"{\\\"10\\\":3,\\\"9\\\":4,\\\"cache\\\":2,\\\"db\\\":1}\""),
  )
}

///|
test "diff reports origins" {
  let result = run(
    parse(
      "{\"operation\":\"diff\",\"old\":{\"layers\":[{\"name\":\"base\",\"value\":{\"db\":{\"port\":1,\"host\":\"h\"}}}]},\"new\":{\"layers\":[{\"name\":\"base\",\"value\":{\"db\":{\"port\":1,\"host\":\"h\"}}},{\"name\":\"prod\",\"value\":{\"db\":{\"port\":2},\"cache\":true}}]}}",
    ),
  )
  assert_eq(test_at(result, ["equal"]), parse("false"))
  assert_eq(test_at(result, ["changes", "0", "path"]), parse("\"/cache\""))
  assert_eq(test_at(result, ["changes", "0", "type"]), parse("\"added\""))
  assert_eq(
    test_at(result, ["changes", "0", "after_origins"]),
    parse("[\"prod\"]"),
  )
  assert_eq(test_at(result, ["changes", "1", "path"]), parse("\"/db/port\""))
  assert_eq(test_at(result, ["changes", "1", "type"]), parse("\"changed\""))
  assert_eq(test_at(result, ["changes", "1", "before"]), parse("1"))
  assert_eq(test_at(result, ["changes", "1", "after"]), parse("2"))
  assert_eq(
    test_at(result, ["changes", "1", "before_origins"]),
    parse("[\"base\"]"),
  )
  assert_eq(
    test_at(result, ["changes", "1", "after_origins"]),
    parse("[\"base\",\"prod\"]"),
  )
}

///|
test "diff cannot see hidden secret changes" {
  let result = run(
    parse(
      "{\"operation\":\"diff\",\"old\":{\"layers\":[{\"name\":\"x\",\"value\":{\"k\":\"${env:S}\"}}],\"env\":{\"S\":\"one\"},\"secret_env\":[\"S\"]},\"new\":{\"layers\":[{\"name\":\"x\",\"value\":{\"k\":\"${env:S}\"}}],\"env\":{\"S\":\"two\"},\"secret_env\":[\"S\"]}}",
    ),
  )
  assert_eq(test_at(result, ["equal"]), parse("true"))
  assert_eq(test_at(result, ["redacted"]), parse("true"))
}

///|
test "diff reports masked override by origin" {
  let result = run(
    parse(
      "{\"operation\":\"diff\",\"old\":{\"layers\":[{\"name\":\"defaults\",\"value\":{\"key\":\"${env:K}\"}}],\"env\":{\"K\":\"k1\"},\"sensitive\":[\"/key\"]},\"new\":{\"layers\":[{\"name\":\"defaults\",\"value\":{\"key\":\"${env:K}\"}},{\"name\":\"tenant\",\"value\":{\"key\":\"hardcoded\"}}],\"env\":{\"K\":\"k1\"},\"sensitive\":[\"/key\"]}}",
    ),
  )
  assert_eq(test_at(result, ["equal"]), parse("false"))
  assert_eq(test_at(result, ["changes", "0", "path"]), parse("\"/key\""))
  assert_eq(
    test_at(result, ["changes", "0", "type"]),
    parse("\"masked_override\""),
  )
  assert_eq(
    test_at(result, ["changes", "0", "before_origins"]),
    parse("[\"defaults\"]"),
  )
  assert_eq(
    test_at(result, ["changes", "0", "after_origins"]),
    parse("[\"defaults\",\"tenant\"]"),
  )
}

///|
test "unknown operation" {
  assert_true(fails("{\"operation\":\"bogus\",\"layers\":[]}"))
}
