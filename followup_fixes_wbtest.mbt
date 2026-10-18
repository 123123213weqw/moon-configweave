///|
test "pointer indices reject numeric expression spellings" {
  let root = record([("a", Array([Number(1.0)]))])
  for path in ["/a/0.0", "/a/00", "/a/0e0"] {
    let bad = try {
      ignore(at(root, path))
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
  assert_eq(at(root, "/a/0"), Number(1.0))
}

///|
test "invalid pointer escapes are rejected" {
  let bad = try {
    ignore(at(record([("a~2", Number(1.0))]), "/a~2"))
    false
  } catch {
    _ => true
  }
  assert_true(bad)
}
