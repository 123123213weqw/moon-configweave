///|
fn escape_key(key : String) -> String {
  key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn segments(pointer : String) -> Array[String] raise InputError {
  if pointer == "" {
    return []
  }
  if !pointer.has_prefix("/") {
    raise InputError("config reference must be a JSON pointer")
  }
  let parts = pointer.split("/").collect()
  ignore(parts.remove(0))
  parts.map(fn(part) {
    part
    .to_string()
    .replace_all(old="~1", new="/")
    .replace_all(old="~0", new="~")
  })
}

///|
fn at(root : Value, pointer : String) -> Value raise {
  let mut current = root
  for part in segments(pointer) {
    match current {
      Object(fields) =>
        current = match fields.get(part) {
          Some(v) => v
          None =>
            raise InputError("missing configuration reference: " + pointer)
        }
      Array(items) => {
        let n = num(parse_value(part)) catch {
          _ => raise InputError("invalid array pointer")
        }
        if n < 0.0 || n.floor() != n || n >= items.length().to_double() {
          raise InputError("array pointer out of range")
        }
        current = items[n.to_int()]
      }
      _ => raise InputError("reference traverses scalar: " + pointer)
    }
  }
  current
}

///|
fn kind(value : Value) -> String {
  match value {
    Null => "null"
    Bool(_) => "boolean"
    Number(_) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn note_origin(
  origins : Map[String, Array[String]],
  path : String,
  source : String,
) -> Unit {
  let history = origins.get(path).unwrap_or([])
  if history.is_empty() || history[history.length() - 1] != source {
    history.push(source)
  }
  origins[path] = history
}

///|
fn track_tree(
  value : Value,
  path : String,
  source : String,
  origins : Map[String, Array[String]],
) -> Unit {
  note_origin(origins, path, source)
  match value {
    Object(fields) =>
      for key, child in fields {
        track_tree(child, path + "/" + escape_key(key), source, origins)
      }
    Array(items) =>
      for i = 0; i < items.length(); i = i + 1 {
        track_tree(items[i], path + "/" + i.to_string(), source, origins)
      }
    _ => ()
  }
}

///|
fn merge(
  base : Value,
  overlay : Value,
  path : String,
  source : String,
  arrays : String,
  strict : Bool,
  origins : Map[String, Array[String]],
  depth : Int,
) -> Value raise {
  if depth > 128 {
    raise InputError("configuration nesting limit")
  }
  note_origin(origins, path, source)
  match (base, overlay) {
    (Object(old), Object(next)) => {
      let result = old.copy()
      for key, value in next {
        let child = path + "/" + escape_key(key)
        result[key] = match old.get(key) {
          Some(previous) =>
            merge(
              previous,
              value,
              child,
              source,
              arrays,
              strict,
              origins,
              depth + 1,
            )
          None => {
            track_tree(value, child, source, origins)
            value
          }
        }
      }
      Object(result)
    }
    (Array(old), Array(next)) if arrays != "replace" => {
      let result = old.copy()
      for value in next {
        if arrays == "append" || !result.contains(value) {
          track_tree(
            value,
            path + "/" + result.length().to_string(),
            source,
            origins,
          )
          result.push(value)
        }
      }
      Array(result)
    }
    _ => {
      if strict &&
        base != Null &&
        overlay != Null &&
        kind(base) != kind(overlay) {
        raise InputError("type-changing overlay at " + path)
      }
      track_tree(overlay, path, source, origins)
      overlay
    }
  }
}

///|
struct Resolution {
  root : Value
  env : Map[String, Value]
  secret_paths : Array[String]
  secret_env : Array[String]
  visiting : Map[String, Bool]
  resolved : Map[String, Value]
  tainted : Map[String, Bool]
}

///|
fn under(path : String, parent : String) -> Bool {
  path == parent || path.has_prefix(parent + "/")
}

///|
fn Resolution::sensitive(self : Resolution, path : String) -> Bool {
  self.secret_paths.any(fn(parent) { under(path, parent) }) ||
  self.tainted.get(path).unwrap_or(false)
}

///|
fn Resolution::reference(
  self : Resolution,
  token : String,
  owner : String,
  depth : Int,
) -> Value raise {
  if token.has_prefix("env:") {
    let name = token.substring(start=4)
    if self.secret_env.contains(name) {
      self.tainted[owner] = true
    }
    match self.env.get(name) {
      Some(v) => v
      None => raise InputError("missing environment variable: " + name)
    }
  } else if token.has_prefix("config:") {
    let path = token.substring(start=7)
    let value = self.resolve(path, depth + 1)
    if self.sensitive(path) ||
      self.secret_paths.any(fn(child) { under(child, path) }) ||
      self.tainted
      .keys()
      .any(fn(child) { under(child, path) && self.tainted[child] }) {
      self.tainted[owner] = true
    }
    value
  } else {
    raise InputError("interpolation must start with env: or config:")
  }
}

///|
fn Resolution::interpolate(
  self : Resolution,
  source : String,
  owner : String,
  depth : Int,
) -> Value raise {
  let mut remaining = source
  let mut result = ""
  while true {
    match remaining.split_once("${") {
      None => return String(result + remaining)
      Some((prefix, suffix)) => {
        let (token, after) = match suffix.split_once("}") {
          Some(pair) => pair
          None => raise InputError("unterminated interpolation at " + owner)
        }
        let value = self.reference(token.to_string(), owner, depth)
        if prefix.is_empty() && result == "" && after.is_empty() {
          return value
        }
        let embedded = match value {
          String(s) => s
          Number(_) | Bool(_) => canonical(value)
          _ => raise InputError("cannot embed structured configuration value")
        }
        result += prefix.to_string() + embedded
        remaining = after.to_string()
      }
    }
  } nobreak {
    raise InputError("interpolation failed")
  }
}

///|
fn Resolution::resolve(
  self : Resolution,
  path : String,
  depth : Int,
) -> Value raise {
  if depth > 128 {
    raise InputError("interpolation depth limit")
  }
  match self.resolved.get(path) {
    Some(v) => return v
    None => ()
  }
  if self.visiting.get(path).unwrap_or(false) {
    raise InputError("interpolation cycle at " + path)
  }
  self.visiting[path] = true
  let value = match at(self.root, path) {
    String(source) => self.interpolate(source, path, depth)
    Object(fields) => {
      let output : Map[String, Value] = Map([])
      for key, _ in fields {
        output[key] = self.resolve(path + "/" + escape_key(key), depth + 1)
      }
      Object(output)
    }
    Array(items) => {
      let output : Array[Value] = []
      for i = 0; i < items.length(); i = i + 1 {
        output.push(self.resolve(path + "/" + i.to_string(), depth + 1))
      }
      Array(output)
    }
    value => value
  }
  self.visiting[path] = false
  self.resolved[path] = value
  value
}

///|
fn Resolution::redact(self : Resolution, value : Value, path : String) -> Value {
  if self.sensitive(path) {
    return String("***")
  }
  match value {
    Object(fields) =>
      Object(
        fields.map(fn(key, child) {
          self.redact(child, path + "/" + escape_key(key))
        }),
      )
    Array(items) => {
      let result : Array[Value] = []
      for i = 0; i < items.length(); i = i + 1 {
        result.push(self.redact(items[i], path + "/" + i.to_string()))
      }
      Array(result)
    }
    other => other
  }
}

///|
fn check_constraints(
  value : Value,
  constraints : Array[Value],
) -> Array[Value] raise {
  let issues : Array[Value] = []
  for constraint in constraints {
    let path = str(get(constraint, "path"))
    let selected = Some(at(value, path)) catch { _ => None }
    let mut message = ""
    match selected {
      None =>
        if truth(get(constraint, "required")) {
          message = "required value missing"
        }
      Some(v) => {
        let expected = optional_str(get(constraint, "type"), "any")
        if expected != "any" && expected != kind(v) {
          message = "type mismatch"
        }
        if get(constraint, "enum") != Null &&
          !arr(get(constraint, "enum")).contains(v) {
          message = "not in enum"
        }
        if get(constraint, "min") != Null {
          if kind(v) != "number" {
            message = "numeric minimum requires number"
          } else if num(v) < num(get(constraint, "min")) {
            message = "below minimum"
          }
        }
        if get(constraint, "max") != Null {
          if kind(v) != "number" {
            message = "numeric maximum requires number"
          } else if num(v) > num(get(constraint, "max")) {
            message = "above maximum"
          }
        }
      }
    }
    if message != "" {
      issues.push(record([("path", String(path)), ("reason", String(message))]))
    }
  }
  issues
}

///|
pub fn run(request : Value) -> Value raise {
  if get(request, "operation") == String("diff") {
    let before = get(run(get(request, "old")), "redacted")
    let after = get(run(get(request, "new")), "redacted")
    let changes : Array[Value] = []
    config_diff(before, after, "", changes)
    return record([
      ("changes", Array(changes)),
      ("equal", Bool(changes.is_empty())),
      ("redacted", Bool(true)),
    ])
  }
  let arrays = optional_str(get(request, "arrays"), "replace")
  if !["replace", "append", "unique"].contains(arrays) {
    raise InputError("unknown array merge strategy")
  }
  let origins : Map[String, Array[String]] = Map([])
  let mut config = Object(Map([]))
  let names : Map[String, Bool] = Map([])
  for layer in arr(get(request, "layers")) {
    let source = str(get(layer, "name"))
    if names.contains(source) {
      raise InputError("duplicate layer name")
    }
    names[source] = true
    let value = get(layer, "value")
    ignore(obj(value))
    config = merge(
      config,
      value,
      "",
      source,
      arrays,
      truth(get(request, "strict_types")),
      origins,
      0,
    )
  }
  let resolution : Resolution = {
    root: config,
    env: if get(request, "env") == Null {
      Map([])
    } else {
      obj(get(request, "env"))
    },
    secret_paths: if get(request, "sensitive") == Null {
      []
    } else {
      string_list(get(request, "sensitive"))
    },
    secret_env: if get(request, "secret_env") == Null {
      []
    } else {
      string_list(get(request, "secret_env"))
    },
    visiting: Map([]),
    resolved: Map([]),
    tainted: Map([]),
  }
  let resolved = resolution.resolve("", 0)
  let constraints = if get(request, "constraints") == Null {
    []
  } else {
    arr(get(request, "constraints"))
  }
  let issues = check_constraints(resolved, constraints)
  let redacted = resolution.redact(resolved, "")
  let history = origins.map(fn(_, sources) { strings(sources) })
  record([
    ("config", if truth(get(request, "reveal")) { resolved } else { redacted }),
    ("redacted", redacted),
    ("origins", Object(history)),
    ("issues", Array(issues)),
    ("valid", Bool(issues.is_empty())),
  ])
}

///|
fn config_diff(
  before : Value,
  after : Value,
  path : String,
  changes : Array[Value],
) -> Unit {
  if before == after {
    return
  }
  match (before, after) {
    (Object(a), Object(b)) => {
      let keys : Map[String, Bool] = Map([])
      for key, _ in a {
        keys[key] = true
      }
      for key, _ in b {
        keys[key] = true
      }
      let sorted = keys.keys().collect()
      sorted.sort()
      for key in sorted {
        let next = path + "/" + escape_key(key)
        if !a.contains(key) {
          changes.push(
            record([
              ("path", String(next)),
              ("type", String("added")),
              ("after", b[key]),
            ]),
          )
        } else if !b.contains(key) {
          changes.push(
            record([
              ("path", String(next)),
              ("type", String("removed")),
              ("before", a[key]),
            ]),
          )
        } else {
          config_diff(a[key], b[key], next, changes)
        }
      }
    }
    _ =>
      changes.push(
        record([
          ("path", String(path)),
          ("type", String("changed")),
          ("before", before),
          ("after", after),
        ]),
      )
  }
}
