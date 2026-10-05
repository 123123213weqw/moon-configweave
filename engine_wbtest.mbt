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
      Array(items) => items[num(parse_value(part)).to_int()]
      _ => raise InputError("invalid test traversal")
    }
  }
  current
}

///|
test "layer merge" {
  let result = run(
    parse_value(
      "{\"layers\":[{\"name\":\"base\",\"value\":{\"db\":{\"host\":\"local\",\"port\":1}}},{\"name\":\"prod\",\"value\":{\"db\":{\"port\":2}}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "db", "host"]), parse_value("\"local\""))
  assert_eq(test_at(result, ["config", "db", "port"]), parse_value("2"))
  assert_eq(
    test_at(result, ["origins", "/db/port"]),
    parse_value("[\"base\",\"prod\"]"),
  )
}

///|
test "interpolation keeps type" {
  let result = run(
    parse_value(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"n\":3,\"copy\":\"${config:/n}\",\"message\":\"n=${config:/n}\"}}]}",
    ),
  )
  assert_eq(test_at(result, ["config", "copy"]), parse_value("3"))
  assert_eq(test_at(result, ["config", "message"]), parse_value("\"n=3\""))
}

///|
test "secret aliases" {
  let result = run(
    parse_value(
      "{\"layers\":[{\"name\":\"x\",\"value\":{\"db\":{\"password\":\"${env:KEY}\"},\"alias\":\"${config:/db}\"}}],\"env\":{\"KEY\":\"secret\"},\"secret_env\":[\"KEY\"]}",
    ),
  )
  assert_eq(
    test_at(result, ["config", "db", "password"]),
    parse_value("\"***\""),
  )
  assert_eq(test_at(result, ["config", "alias"]), parse_value("\"***\""))
}

///|
test "unique arrays" {
  let result = run(
    parse_value(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":[1,2]}},{\"name\":\"b\",\"value\":{\"x\":[2,3]}}],\"arrays\":\"unique\"}",
    ),
  )
  assert_eq(test_at(result, ["config", "x"]), parse_value("[1,2,3]"))
}

///|
test "missing env" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":\"${env:MISSING}\"}}]}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "cycle" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"layers\":[{\"name\":\"x\",\"value\":{\"a\":\"${config:/b}\",\"b\":\"${config:/a}\"}}]}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "type conflict" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":1}},{\"name\":\"b\",\"value\":{\"x\":\"a\"}}],\"strict_types\":true}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "numeric constraint wrong type" {
  let result = run(
    parse_value(
      "{\"layers\":[{\"name\":\"a\",\"value\":{\"x\":\"text\"}}],\"constraints\":[{\"path\":\"/x\",\"min\":1}]}",
    ),
  )
  assert_eq(test_at(result, ["valid"]), parse_value("false"))
}
