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
test "per-path array strategies" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"steps\":[\"checkout\"],\"targets\":[\"js\"],\"ignored\":[1]}},{\"name\":\"b\",\"value\":{\"steps\":[\"test\"],\"targets\":[\"js\",\"wasm\"],\"ignored\":[2]}}],\"arrays\":{\"append\":[\"/steps\"],\"unique\":[\"/targets\"]}}",
    ),
  )
  assert_eq(
    test_at(result, ["config", "steps"]),
    parse("[\"checkout\",\"test\"]"),
  )
  assert_eq(test_at(result, ["config", "targets"]), parse("[\"js\",\"wasm\"]"))
  assert_eq(test_at(result, ["config", "ignored"]), parse("[2]"))
}

///|
test "per-path strategy default" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[1],\"y\":[1]}},{\"name\":\"b\",\"value\":{\"x\":[2],\"y\":[2]}}],\"arrays\":{\"default\":\"append\",\"replace\":[\"/x\"]}}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse("[2]"))
  assert_eq(test_at(result, ["config", "y"]), parse("[1,2]"))
}

///|
test "array strategy assigned twice" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[]}}],\"arrays\":{\"append\":[\"/x\"],\"unique\":[\"/x\"]}}",
    ),
  )
}

///|
test "unknown path strategy" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[]}}],\"arrays\":{\"merge\":[\"/x\"]}}",
    ),
  )
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
test "shadowed overrides are listed" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"defaults\",\"value\":{\"db\":{\"port\":1},\"same\":7}},{\"name\":\"prod\",\"value\":{\"db\":{\"port\":2},\"same\":7}}]}",
    ),
  )
  assert_eq(test_at(result, ["shadowed", "0", "path"]), parse("\"/db/port\""))
  assert_eq(test_at(result, ["shadowed", "0", "layer"]), parse("\"defaults\""))
  assert_eq(test_at(result, ["shadowed", "0", "by"]), parse("\"prod\""))
}

///|
test "identical overlay is not shadowing" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}},{\"name\":\"b\",\"value\":{\"x\":1}}]}",
    ),
  )
  assert_eq(test_at(result, ["shadowed"]), parse("[]"))
  assert_eq(test_at(result, ["config", "x"]), parse("1"))
}

///|
test "shadowing follows layer order" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}},{\"name\":\"b\",\"value\":{\"x\":2}},{\"name\":\"c\",\"value\":{\"x\":3}}]}",
    ),
  )
  assert_eq(test_at(result, ["shadowed", "0", "layer"]), parse("\"a\""))
  assert_eq(test_at(result, ["shadowed", "0", "by"]), parse("\"b\""))
  assert_eq(test_at(result, ["shadowed", "1", "layer"]), parse("\"b\""))
  assert_eq(test_at(result, ["shadowed", "1", "by"]), parse("\"c\""))
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
test "env reference default" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"missing\":\"${env:NOPE:-fallback}\",\"present\":\"${env:SET:-unused}\"}}],\"env\":{\"SET\":\"value\"}}",
    ),
  )
  assert_eq(test_at(result, ["config", "missing"]), parse("\"fallback\""))
  assert_eq(test_at(result, ["config", "present"]), parse("\"value\""))
}

///|
test "config reference default" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"n\":5,\"missing\":\"${config:/nope:-zero}\",\"present\":\"${config:/n:-0}\"}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "missing"]), parse("\"zero\""))
  assert_eq(test_at(result, ["config", "present"]), parse("5"))
}

///|
test "empty env value is present" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":\"${env:EMPTY:-fallback}\"}}],\"env\":{\"EMPTY\":\"\"}}",
    ),
  )
  assert_eq(test_at(result, ["config", "a"]), parse("\"\""))
}

///|
test "fallback does not unmask secrets" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"combo\":\"a=${env:S}-${env:NOPE:-plain}\"}}],\"env\":{\"S\":\"sec\"},\"secret_env\":[\"S\"]}",
    ),
  )
  assert_eq(test_at(result, ["config", "combo"]), parse("\"***\""))
  assert_eq(test_at(result, ["masked"]), parse("[\"/combo\"]"))
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
test "sensitive keys mask by name" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"db\":{\"password\":\"pw\",\"host\":\"h\",\"Password\":\"case\"},\"api\":{\"token\":\"t\"},\"alias\":\"${config:/db}\"}}],\"sensitive_keys\":[\"password\",\"token\"]}",
    ),
  )
  assert_eq(test_at(result, ["config", "db", "password"]), parse("\"***\""))
  assert_eq(test_at(result, ["config", "api", "token"]), parse("\"***\""))
  assert_eq(test_at(result, ["config", "db", "host"]), parse("\"h\""))
  assert_eq(test_at(result, ["config", "db", "Password"]), parse("\"case\""))
  assert_eq(test_at(result, ["config", "alias"]), parse("\"***\""))
  assert_eq(
    test_at(result, ["masked"]),
    parse("[\"/alias\",\"/api/token\",\"/db/password\"]"),
  )
}

///|
test "empty sensitive key rejected" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":1}}],\"sensitive_keys\":[\"\"]}",
    ),
  )
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
test "pattern constraints" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"version\":\"v12\",\"stage\":\"prod\",\"name\":\"abc\",\"tags\":[\"a\",\"b\"]}}],\"constraints\":[{\"path\":\"/version\",\"pattern\":\"^v[0-9]+$\"},{\"path\":\"/stage\",\"pattern\":\"^(dev|prod)$\"},{\"path\":\"/name\",\"min_length\":2,\"max_length\":8},{\"path\":\"/tags\",\"min_length\":1,\"max_length\":3}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse("true"))
  assert_eq(test_at(result, ["issues"]), parse("[]"))
}

///|
test "pattern mismatch" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"version\":\"latest\"}}],\"constraints\":[{\"path\":\"/version\",\"pattern\":\"^v[0-9]+$\"}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse("false"))
  assert_eq(
    test_at(result, ["issues", "0", "reason"]),
    parse("\"pattern mismatch\""),
  )
}

///|
test "pattern requires string" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"version\":12}}],\"constraints\":[{\"path\":\"/version\",\"pattern\":\"^v[0-9]+$\"}]}",
    ),
  )
  assert_eq(
    test_at(result, ["issues", "0", "reason"]),
    parse("\"pattern requires string\""),
  )
}

///|
test "invalid constraint pattern" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":\"a\"}}],\"constraints\":[{\"path\":\"/x\",\"pattern\":\"(unclosed\"}]}",
    ),
  )
}

///|
test "length violations" {
  let result = run(
    parse(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"name\":\"ab\",\"tags\":[\"a\",\"b\",\"c\"],\"n\":5}}],\"constraints\":[{\"path\":\"/name\",\"min_length\":3},{\"path\":\"/tags\",\"max_length\":2},{\"path\":\"/n\",\"min_length\":1}]}",
    ),
  )
  assert_eq(
    test_at(result, ["issues", "0", "reason"]),
    parse("\"below minimum length\""),
  )
  assert_eq(
    test_at(result, ["issues", "1", "reason"]),
    parse("\"above maximum length\""),
  )
  assert_eq(
    test_at(result, ["issues", "2", "reason"]),
    parse("\"length requires string or array\""),
  )
}

///|
test "unknown constraint clause" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}}],\"constraints\":[{\"path\":\"/x\",\"maximum\":3}]}",
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
test "flat export maps pointers to leaves" {
  let result = run(
    parse(
      "{\"operation\":\"export\",\"format\":\"flat\",\"layers\":[{\"name\":\"x\",\"value\":{\"b\":{\"c\":[1,{\"d\":null}]},\"a\":1}}]}",
    ),
  )
  assert_eq(test_at(result, ["format"]), parse("\"flat\""))
  assert_eq(
    test_at(result, ["text"]),
    parse("\"{\\\"/a\\\":1,\\\"/b/c/0\\\":1,\\\"/b/c/1/d\\\":null}\""),
  )
}

///|
test "dotenv export" {
  let result = run(
    parse(
      "{\"operation\":\"export\",\"format\":\"dotenv\",\"layers\":[{\"name\":\"x\",\"value\":{\"database\":{\"host\":\"db.example\",\"port\":5432,\"password\":\"${env:P}\"},\"debug\":true,\"motd\":\"hello world #1\",\"empty\":\"\"}}],\"env\":{\"P\":\"pw\"},\"secret_env\":[\"P\"]}",
    ),
  )
  assert_eq(test_at(result, ["format"]), parse("\"dotenv\""))
  assert_eq(
    test_at(result, ["text"]),
    parse(
      "\"DATABASE_HOST=db.example\\nDATABASE_PASSWORD=***\\nDATABASE_PORT=5432\\nDEBUG=true\\nEMPTY=\\\"\\\"\\nMOTD=\\\"hello world #1\\\"\\n\"",
    ),
  )
}

///|
test "dotenv key collision" {
  assert_true(
    fails(
      "{\"operation\":\"export\",\"format\":\"dotenv\",\"layers\":[{\"name\":\"x\",\"value\":{\"a-b\":1,\"a_b\":2}}]}",
    ),
  )
}

///|
test "unknown export format" {
  assert_true(
    fails(
      "{\"operation\":\"export\",\"format\":\"yaml\",\"layers\":[{\"name\":\"x\",\"value\":{\"a\":1}}]}",
    ),
  )
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
test "diff ignores designated subtrees" {
  let result = run(
    parse(
      "{\"operation\":\"diff\",\"ignore\":[\"/build\",\"/meta/stamp\"],\"old\":{\"layers\":[{\"name\":\"a\",\"value\":{\"build\":{\"time\":1,\"host\":\"x\"},\"meta\":{\"stamp\":1,\"owner\":\"ops\"},\"port\":1}}]},\"new\":{\"layers\":[{\"name\":\"a\",\"value\":{\"build\":{\"time\":2,\"host\":\"y\"},\"meta\":{\"stamp\":2,\"owner\":\"ops\"},\"port\":2}}]}}",
    ),
  )
  assert_eq(test_at(result, ["equal"]), parse("false"))
  assert_eq(test_at(result, ["changes", "0", "path"]), parse("\"/port\""))
  assert_eq(test_at(result, ["ignored"]), parse("[\"/build\",\"/meta/stamp\"]"))
}

///|
test "diff is equal when only ignored paths differ" {
  let result = run(
    parse(
      "{\"operation\":\"diff\",\"ignore\":[\"/build\"],\"old\":{\"layers\":[{\"name\":\"a\",\"value\":{\"build\":{\"time\":1},\"port\":1}}]},\"new\":{\"layers\":[{\"name\":\"a\",\"value\":{\"build\":{\"time\":2},\"port\":1}}]}}",
    ),
  )
  assert_eq(test_at(result, ["equal"]), parse("true"))
  assert_eq(test_at(result, ["changes"]), parse("[]"))
}

///|
test "unknown operation" {
  assert_true(fails("{\"operation\":\"bogus\",\"layers\":[]}"))
}

///|
test "infer derives constraints from observations" {
  let result = run(
    parse(
      "{\"operation\":\"infer\",\"layers\":[{\"name\":\"dev\",\"value\":{\"db\":{\"host\":\"db.dev\",\"port\":5432,\"level\":\"debug\"}}},{\"name\":\"prod\",\"value\":{\"db\":{\"host\":\"db.prod\",\"port\":6543,\"level\":\"info\",\"password\":\"pw\"}}}],\"sensitive\":[\"/db/password\"]}",
    ),
  )
  assert_eq(
    test_at(result, ["constraints", "0", "path"]),
    parse("\"/db/host\""),
  )
  assert_eq(test_at(result, ["constraints", "0", "type"]), parse("\"string\""))
  assert_eq(
    test_at(result, ["constraints", "0", "enum"]),
    parse("[\"db.dev\",\"db.prod\"]"),
  )
  assert_eq(
    test_at(result, ["constraints", "2", "path"]),
    parse("\"/db/port\""),
  )
  assert_eq(test_at(result, ["constraints", "2", "min"]), parse("5432"))
  assert_eq(test_at(result, ["constraints", "2", "max"]), parse("6543"))
  assert_eq(test_at(result, ["constraint_count"]), parse("3"))
  assert_eq(test_at(result, ["path_count"]), parse("3"))
  assert_eq(test_at(result, ["valid"]), parse("true"))
}

///|
test "infer never reports masked paths" {
  let result = run(
    parse(
      "{\"operation\":\"infer\",\"layers\":[{\"name\":\"a\",\"value\":{\"password\":\"pw\"}},{\"name\":\"b\",\"value\":{\"password\":\"pw2\"}}],\"sensitive\":[\"/password\"]}",
    ),
  )
  assert_eq(test_at(result, ["constraints"]), parse("[]"))
  assert_eq(test_at(result, ["constraint_count"]), parse("0"))
  assert_eq(test_at(result, ["valid"]), parse("true"))
}

///|
test "infer max_enum bounds enums" {
  let result = run(
    parse(
      "{\"operation\":\"infer\",\"max_enum\":1,\"layers\":[{\"name\":\"a\",\"value\":{\"host\":\"one\",\"port\":1}},{\"name\":\"b\",\"value\":{\"host\":\"two\",\"port\":2}}]}",
    ),
  )
  assert_eq(test_at(result, ["constraints", "0", "type"]), parse("\"string\""))
  assert_eq(test_at(result, ["constraints", "1", "min"]), parse("1"))
  assert_eq(test_at(result, ["constraints", "1", "max"]), parse("2"))
}

///|
test "infer mixed types omit the type clause" {
  let result = run(
    parse(
      "{\"operation\":\"infer\",\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}},{\"name\":\"b\",\"value\":{\"x\":\"one\"}}]}",
    ),
  )
  assert_eq(test_at(result, ["constraints", "0", "path"]), parse("\"/x\""))
  assert_eq(test_at(result, ["constraints", "0", "required"]), parse("true"))
}

///|
test "infer rejects bad max_enum" {
  assert_true(
    fails(
      "{\"operation\":\"infer\",\"max_enum\":0,\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}}]}",
    ),
  )
}

///|
test "followup value-free secret audit" {
  let result = run(
    parse(
      "{\"operation\":\"audit\",\"layers\":[{\"name\":\"base\",\"value\":{\"db\":{\"password\":\"fixture-secret\",\"port\":1}}},{\"name\":\"prod\",\"value\":{\"db\":{\"port\":2}}}],\"sensitive\":[\"/db/password\"],\"reveal\":true}",
    ),
  )
  assert_eq(test_at(result, ["values_included"]), parse("false"))
  assert_eq(test_at(result, ["path_count"]), parse("4"))
  assert_eq(test_at(result, ["masked"]), parse("[\"/db/password\"]"))
  assert_eq(test_at(result, ["paths", "2", "type"]), parse("\"redacted\""))
  assert_eq(
    test_at(result, ["paths", "3", "layers"]),
    parse("[\"base\",\"prod\"]"),
  )
  assert_eq(test_at(result, ["valid"]), parse("true"))
}

///|
test "followup empty audit" {
  let result = run(parse("{\"operation\":\"audit\",\"layers\":[]}"))
  assert_eq(test_at(result, ["path_count"]), parse("1"))
  assert_eq(test_at(result, ["values_included"]), parse("false"))
}

///|
test "followup canonical pointer error" {
  assert_true(
    fails(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":[1],\"b\":\"${config:/a/0.0}\"}}]}",
    ),
  )
}
