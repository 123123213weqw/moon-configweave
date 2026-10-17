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
  parts.map(part => {
    part
    .to_owned()
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
        let n = num(parse(part)) catch {
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
let kinds : Array[String] = [
  "any", "null", "boolean", "number", "string", "array", "object",
]

///|
let strategies : Array[String] = ["replace", "append", "unique"]

///|
let clauses : Array[String] = [
  "path", "required", "type", "enum", "pattern", "min_length", "max_length", "min",
  "max",
]

///|
/// Array merge strategy: one default mode plus optional per-path overrides.
/// Per-path keys are JSON Pointers matched exactly against merge paths.
priv struct ArrayStrategy {
  default : String
  per_path : Map[String, String]
}

///|
fn canonical_pointer(pointer : String) -> String raise {
  "/" + segments(pointer).map(escape_key).join("/")
}

///|
fn array_strategy(request : Value) -> ArrayStrategy raise {
  match get(request, "arrays") {
    Null => { default: "replace", per_path: Map([]), }
    String(mode) =>
      if strategies.contains(mode) {
        { default: mode, per_path: Map([]), }
      } else {
        raise InputError("unknown array merge strategy: " + mode)
      }
    Object(fields) => {
      let result : Map[String, String] = Map([])
      let default = optional_str(
        fields.get("default").unwrap_or(Null),
        "replace",
      )
      if !strategies.contains(default) {
        raise InputError("unknown array merge strategy: " + default)
      }
      for key, value in fields {
        if key == "default" {
          continue
        }
        if !strategies.contains(key) {
          raise InputError("unknown array merge strategy: " + key)
        }
        for pointer in string_list(value) {
          let normalized = canonical_pointer(pointer)
          if result.contains(normalized) {
            raise InputError("array strategy assigned twice: " + normalized)
          }
          result[normalized] = key
        }
      }
      { default, per_path: result, }
    }
    _ => raise InputError("arrays must be a strategy or a path map")
  }
}

///|
fn ArrayStrategy::at(self : ArrayStrategy, path : String) -> String {
  self.per_path.get(path).unwrap_or(self.default)
}

///|
let nesting_limit : Int32 = 128

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
  arrays : ArrayStrategy,
  strict : Bool,
  origins : Map[String, Array[String]],
  shadowed : Array[(String, String, String)],
  depth : Int32,
) -> Value raise {
  if depth > nesting_limit {
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
              shadowed,
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
    (Array(old), Array(next)) if arrays.at(path) != "replace" => {
      let result = old.copy()
      for value in next {
        if arrays.at(path) == "append" || !result.contains(value) {
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
      // This layer replaced a different value: name the layer it overrode.
      if base != overlay {
        let history = origins.get(path).unwrap_or([])
        if history.length() >= 2 && history[history.length() - 2] != source {
          shadowed.push((path, history[history.length() - 2], source))
        }
      }
      track_tree(overlay, path, source, origins)
      overlay
    }
  }
}

///|
priv struct Resolution {
  root : Value
  env : Map[String, Value]
  secret_paths : Array[String]
  secret_keys : Array[String]
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
/// The unescaped last key of a pointer, or "" for the root.
fn last_key(path : String) -> String {
  match path.rev_find("/") {
    Some(index) =>
      path[index + 1:]
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    None => ""
  }
}

///|
fn Resolution::sensitive(self : Resolution, path : String) -> Bool {
  self.secret_paths.any(parent => under(path, parent)) ||
  (path != "" && self.secret_keys.contains(last_key(path))) ||
  self.tainted.get(path).unwrap_or(false)
}

///|
/// Whether any path strictly below `path` in the merged tree is sensitive by
/// designation (explicit path or key name).
fn Resolution::hides_secret(
  self : Resolution,
  value : Value,
  path : String,
) -> Bool {
  match value {
    Object(fields) =>
      fields
      .iter()
      .any(entry => {
        let child = path + "/" + escape_key(entry.0)
        self.sensitive(child) || self.hides_secret(entry.1, child)
      })
    Array(items) => {
      for i = 0; i < items.length(); i = i + 1 {
        let child = path + "/" + i.to_string()
        if self.sensitive(child) || self.hides_secret(items[i], child) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Whether a pointer resolves inside root; a pointer that traverses a scalar
/// or leaves an array counts as absent, so it can fall back to a default.
fn present(root : Value, pointer : String) -> Bool raise {
  let mut current = root
  for part in segments(pointer) {
    match current {
      Object(fields) =>
        current = match fields.get(part) {
          Some(v) => v
          None => return false
        }
      Array(items) => {
        let n = num(parse(part)) catch { _ => return false }
        if n < 0.0 || n.floor() != n || n >= items.length().to_double() {
          return false
        }
        current = items[n.to_int()]
      }
      _ => return false
    }
  }
  true
}

///|
/// A reference is `${env:NAME}`, `${config:/pointer}` or either form with a
/// `:-literal` fallback used only when the target is absent.
fn Resolution::reference(
  self : Resolution,
  token : String,
  owner : String,
  depth : Int32,
) -> Value raise {
  let (target, fallback) = match token.split_once(":-") {
    Some((name, text)) => (name.to_owned(), Some(text.to_owned()))
    None => (token, None)
  }
  if target.has_prefix("env:") {
    let name = target[4:].to_owned()
    match self.env.get(name) {
      Some(v) => {
        if self.secret_env.contains(name) {
          self.tainted[owner] = true
        }
        v
      }
      None =>
        match fallback {
          Some(text) => String(text)
          None => raise InputError("missing environment variable: " + name)
        }
    }
  } else if target.has_prefix("config:") {
    let path = target[7:].to_owned()
    if !present(self.root, path) {
      match fallback {
        Some(text) => return String(text)
        None => raise InputError("missing configuration reference: " + path)
      }
    }
    let value = self.resolve(path, depth + 1)
    if self.sensitive(path) ||
      self.hides_secret(at(self.root, path), path) ||
      self.tainted
      .keys()
      .any(child => under(child, path) && self.tainted[child]) {
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
  depth : Int32,
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
        let value = self.reference(token.to_owned(), owner, depth)
        if prefix.is_empty() && result == "" && after.is_empty() {
          return value
        }
        let embedded = match value {
          String(s) => s
          Number(_) | Bool(_) => canonical(value)
          _ => raise InputError("cannot embed structured configuration value")
        }
        result += prefix.to_owned() + embedded
        remaining = after.to_owned()
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
  depth : Int32,
) -> Value raise {
  if depth > nesting_limit {
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
fn Resolution::redact(
  self : Resolution,
  value : Value,
  path : String,
  masked : Array[String],
) -> Value {
  if self.sensitive(path) {
    masked.push(path)
    return String("***")
  }
  match value {
    Object(fields) =>
      Object(
        fields.map((key, child) => {
          self.redact(child, path + "/" + escape_key(key), masked)
        }),
      )
    Array(items) => {
      let result : Array[Value] = []
      for i = 0; i < items.length(); i = i + 1 {
        result.push(self.redact(items[i], path + "/" + i.to_string(), masked))
      }
      Array(result)
    }
    other => other
  }
}

///|
/// Returns the first violated clause of a constraint, checked in the fixed
/// order type, enum, pattern, min_length, max_length, min, max, or "" when
/// the value satisfies all of them. Patterns are unanchored searches in the
/// toolchain's regex dialect; lengths count UTF-16 code units of strings or
/// elements of arrays.
fn violation(value : Value, constraint : Value) -> String raise {
  let expected = optional_str(get(constraint, "type"), "any")
  if !kinds.contains(expected) {
    raise InputError("unknown constraint type: " + expected)
  }
  if expected != "any" && expected != kind(value) {
    return "type mismatch"
  }
  if get(constraint, "enum") != Null &&
    !arr(get(constraint, "enum")).contains(value) {
    return "not in enum"
  }
  if get(constraint, "pattern") != Null {
    let pattern = str(get(constraint, "pattern"))
    let regex = @string.Regex::Regex(pattern) catch {
      _ => raise InputError("invalid constraint pattern: " + pattern)
    }
    match value {
      String(text) =>
        if regex.execute(text) is None {
          return "pattern mismatch"
        }
      _ => return "pattern requires string"
    }
  }
  let length = match value {
    String(text) => Some(text.length())
    Array(items) => Some(items.length())
    _ => None
  }
  if get(constraint, "min_length") != Null {
    match length {
      None => return "length requires string or array"
      Some(n) =>
        if n.to_double() < num(get(constraint, "min_length")) {
          return "below minimum length"
        }
    }
  }
  if get(constraint, "max_length") != Null {
    match length {
      None => return "length requires string or array"
      Some(n) =>
        if n.to_double() > num(get(constraint, "max_length")) {
          return "above maximum length"
        }
    }
  }
  if get(constraint, "min") != Null {
    if kind(value) != "number" {
      return "numeric minimum requires number"
    }
    if num(value) < num(get(constraint, "min")) {
      return "below minimum"
    }
  }
  if get(constraint, "max") != Null {
    if kind(value) != "number" {
      return "numeric maximum requires number"
    }
    if num(value) > num(get(constraint, "max")) {
      return "above maximum"
    }
  }
  ""
}

///|
fn check_constraints(
  value : Value,
  constraints : Array[Value],
) -> Array[Value] raise {
  let issues : Array[Value] = []
  for constraint in constraints {
    for clause, _ in obj(constraint) {
      if !clauses.contains(clause) {
        raise InputError("unknown constraint clause: " + clause)
      }
    }
    let path = str(get(constraint, "path"))
    ignore(segments(path))
    let selected = Some(at(value, path)) catch { _ => None }
    let message = match selected {
      None =>
        if truth(get(constraint, "required")) {
          "required value missing"
        } else {
          ""
        }
      Some(v) => violation(v, constraint)
    }
    if message != "" {
      issues.push(record([("path", String(path)), ("reason", String(message))]))
    }
  }
  issues
}

///|
fn describe_layers(layers : Array[Value]) -> Value raise {
  Array(
    layers.map(layer => {
      let fields = [("name", get(layer, "name"))]
      if get(layer, "source") != Null {
        fields.push(("source", String(str(get(layer, "source")))))
      }
      record(fields)
    }),
  )
}

///|
fn merge_report(request : Value) -> Value raise {
  let arrays = array_strategy(request)
  let origins : Map[String, Array[String]] = Map([])
  let shadowed : Array[(String, String, String)] = []
  let mut config = Object(Map([]))
  let names : Map[String, Bool] = Map([])
  let layers = arr(get(request, "layers"))
  for layer in layers {
    let source = str(get(layer, "name"))
    if names.contains(source) {
      raise InputError("duplicate layer name: " + source)
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
      shadowed,
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
    secret_paths: optional_strings(get(request, "sensitive")),
    secret_keys: optional_strings(get(request, "sensitive_keys")),
    secret_env: optional_strings(get(request, "secret_env")),
    visiting: Map([]),
    resolved: Map([]),
    tainted: Map([]),
  }
  for path in resolution.secret_paths {
    ignore(segments(path))
  }
  if resolution.secret_keys.contains("") {
    raise InputError("sensitive key names must not be empty")
  }
  let resolved = resolution.resolve("", 0)
  let constraints = if get(request, "constraints") == Null {
    []
  } else {
    arr(get(request, "constraints"))
  }
  let issues = check_constraints(resolved, constraints)
  let masked : Array[String] = []
  let redacted = resolution.redact(resolved, "", masked)
  sort_lexical(masked)
  let history = origins.map((_, sources) => strings(sources))
  shadowed.sort_by((a, b) => {
    String::lexical_compare(a.0 + "\u{0}" + a.1, b.0 + "\u{0}" + b.1)
  })
  record([
    ("config", if truth(get(request, "reveal")) { resolved } else { redacted }),
    ("redacted", redacted),
    ("masked", strings(masked)),
    (
      "shadowed",
      Array(
        shadowed.map(entry => {
          record([
            ("path", String(entry.0)),
            ("layer", String(entry.1)),
            ("by", String(entry.2)),
          ])
        }),
      ),
    ),
    ("origins", Object(history)),
    ("layers", describe_layers(layers)),
    ("issues", Array(issues)),
    ("valid", Bool(issues.is_empty())),
  ])
}

///|
let formats : Array[String] = ["json", "flat", "dotenv"]

///|
/// dotenv key for a pointer: segments upper-cased, anything outside ASCII
/// letters and digits becomes "_", segments joined with "_".
fn dotenv_key(pointer : String) -> String raise {
  segments(pointer)
  .map(segment => {
    segment
    .to_upper()
    .iter()
    .map(c => {
      if c.is_ascii_alphabetic() || c.is_ascii_digit() {
        c
      } else {
        '_'
      }
    })
    .collect()
    |> String::from_array
  })
  .join("_")
}

///|
/// A dotenv value is written bare when it is a plain string without
/// whitespace, quotes, "#" or "=", and JSON-quoted otherwise; non-string
/// leaves use their JSON form.
fn dotenv_value(value : Value) -> String {
  match value {
    String(text) =>
      if text != "" &&
        !text
        .iter()
        .any(c => {
          c == ' ' ||
          c == '\t' ||
          c == '\n' ||
          c == '\r' ||
          c == '"' ||
          c == '\'' ||
          c == '#' ||
          c == '='
        }) {
        text
      } else {
        value.stringify()
      }
    other => canonical(other)
  }
}

///|
fn render_export(config : Value, format : String) -> String raise {
  match format {
    "json" => canonical(config)
    "flat" => canonical(Object(config.flatten()))
    _ => {
      let flat = config.flatten()
      let keys : Map[String, String] = Map([])
      let lines : Array[String] = []
      for pointer, _ in flat {
        let key = dotenv_key(pointer)
        match keys.get(key) {
          Some(other) =>
            raise InputError(
              "dotenv key collision: " +
              key +
              " from " +
              other +
              " and " +
              pointer,
            )
          None => keys[key] = pointer
        }
      }
      let names = keys.keys().collect()
      sort_lexical(names)
      for name in names {
        lines.push(name + "=" + dotenv_value(flat[keys[name]]))
      }
      lines.join("\n") + "\n"
    }
  }
}

///|
fn export_report(request : Value) -> Value raise {
  let format = optional_str(get(request, "format"), "json")
  if !formats.contains(format) {
    raise InputError("unknown export format: " + format)
  }
  let report = merge_report(request)
  record([
    ("text", String(render_export(get(report, "config"), format))),
    ("format", String(format)),
    ("redacted", Bool(!truth(get(request, "reveal")))),
    ("layers", get(report, "layers")),
    ("issues", get(report, "issues")),
    ("valid", get(report, "valid")),
  ])
}

///|
fn diff_report(request : Value) -> Value raise {
  let before = merge_report(get(request, "old"))
  let after = merge_report(get(request, "new"))
  let ignored = optional_strings(get(request, "ignore")).map(canonical_pointer)
  let changes : Array[Value] = []
  config_diff(
    get(before, "redacted"),
    get(after, "redacted"),
    "",
    changes,
    get(before, "origins"),
    get(after, "origins"),
  )
  // Hidden values compare equal, so an override of a secret is reported
  // through its origin chain instead.
  let before_masked = string_list(get(before, "masked"))
  let after_masked = string_list(get(after, "masked"))
  for path in before_masked {
    if after_masked.contains(path) {
      let previous = get(get(before, "origins"), path)
      let current = get(get(after, "origins"), path)
      if previous != current {
        changes.push(
          record([
            ("path", String(path)),
            ("type", String("masked_override")),
            ("before_origins", previous),
            ("after_origins", current),
          ]),
        )
      }
    }
  }
  // Ignored subtrees are dropped after the walk so masked overrides are filtered too.
  let kept = changes.filter(change => {
    !ignored.any(parent => {
      under(str(get(change, "path")) catch { _ => "" }, parent)
    })
  })
  record([
    ("changes", Array(kept)),
    ("equal", Bool(kept.is_empty())),
    ("ignored", strings(ignored)),
    ("redacted", Bool(true)),
  ])
}

///|
pub fn run(request : Value) -> Value raise {
  match get(request, "operation") {
    Null | String("merge") => merge_report(request)
    String("diff") => diff_report(request)
    String("export") => export_report(request)
    String(other) => raise InputError("unknown operation: " + other)
    _ => raise InputError("operation must be a string")
  }
}

///|
fn change(
  path : String,
  kind : String,
  values : Array[(String, Value)],
  before_origins : Value,
  after_origins : Value,
) -> Value {
  let fields = [("path", String(path)), ("type", String(kind))]
  for pair in values {
    fields.push(pair)
  }
  if get(before_origins, path) != Null {
    fields.push(("before_origins", get(before_origins, path)))
  }
  if get(after_origins, path) != Null {
    fields.push(("after_origins", get(after_origins, path)))
  }
  record(fields)
}

///|
fn config_diff(
  before : Value,
  after : Value,
  path : String,
  changes : Array[Value],
  before_origins : Value,
  after_origins : Value,
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
      sort_lexical(sorted)
      for key in sorted {
        let next = path + "/" + escape_key(key)
        if !a.contains(key) {
          changes.push(
            change(
              next,
              "added",
              [("after", b[key])],
              before_origins,
              after_origins,
            ),
          )
        } else if !b.contains(key) {
          changes.push(
            change(
              next,
              "removed",
              [("before", a[key])],
              before_origins,
              after_origins,
            ),
          )
        } else {
          config_diff(
            a[key],
            b[key],
            next,
            changes,
            before_origins,
            after_origins,
          )
        }
      }
    }
    _ =>
      changes.push(
        change(
          path,
          "changed",
          [("before", before), ("after", after)],
          before_origins,
          after_origins,
        ),
      )
  }
}
