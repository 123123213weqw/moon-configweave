///|
fn audit_tree(
  value : Value,
  path : String,
  origins : Value,
  masked : Array[String],
  entries : Array[Value],
) -> Unit raise {
  let secret = masked.contains(path)
  let history = get(origins, path)
  entries.push(
    record([
      ("path", String(path)),
      ("type", String(if secret { "redacted" } else { kind(value) })),
      ("masked", Bool(secret)),
      ("layers", if history == Null { Array([]) } else { history }),
    ]),
  )
  if secret {
    return
  }
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      sort_lexical(keys)
      for key in keys {
        audit_tree(
          fields[key],
          path + "/" + escape_key(key),
          origins,
          masked,
          entries,
        )
      }
    }
    Array(items) =>
      for i = 0; i < items.length(); i = i + 1 {
        audit_tree(
          items[i],
          path + "/" + i.to_string(),
          origins,
          masked,
          entries,
        )
      }
    _ => ()
  }
}

///|
fn audit_report(request : Value) -> Value raise {
  let report = merge_report(request)
  let entries : Array[Value] = []
  let masked = string_list(get(report, "masked"))
  audit_tree(
    get(report, "redacted"),
    "",
    get(report, "origins"),
    masked,
    entries,
  )
  record([
    ("paths", Array(entries)),
    ("path_count", Number(entries.length().to_double())),
    ("masked", strings(masked)),
    ("issues", get(report, "issues")),
    ("valid", get(report, "valid")),
    ("values_included", Bool(false)),
  ])
}
