///|
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[Value])
  Object(Map[String, Value])
} derive(Eq, Debug)

///|
pub fn from_json(value : Json) -> Value {
  match value {
    Json::Null => Null
    Json::True => Bool(true)
    Json::False => Bool(false)
    Json::Number(n, ..) => Number(n)
    Json::String(s) => String(s)
    Json::Array(items) => Array(items.map(from_json))
    Json::Object(fields) => Object(fields.map(fn(_, v) { from_json(v) }))
  }
}

///|
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Number(n) => Json::number(n)
    String(s) => Json::string(s)
    Array(items) => Json::array(items.map(fn(v) { v.to_json() }))
    Object(fields) => Json::object(fields.map(fn(_, v) { v.to_json() }))
  }
}

///|
pub fn Value::stringify(self : Value) -> String {
  self.to_json().stringify()
}

///|
/// Parses JSON text into a semantic value.
pub fn parse(source : StringView) -> Value raise {
  from_json(@json.parse(source))
}

///|
pub fn execute(request : Json) -> Json raise {
  run(from_json(request)).to_json()
}

///|
/// Maps every leaf (a scalar or an empty container) to its JSON Pointer
/// path. The root path is "" and keys are escaped as in RFC 6901.
pub fn Value::flatten(self : Value) -> Map[String, Value] {
  let result : Map[String, Value] = Map([])
  fn walk(value : Value, path : String) -> Unit {
    match value {
      Object(fields) if !fields.is_empty() =>
        for key, child in fields {
          walk(child, path + "/" + escape_key(key))
        }
      Array(items) if !items.is_empty() =>
        for i, item in items {
          walk(item, path + "/" + i.to_string())
        }
      leaf => result[path] = leaf
    }
  }

  walk(self, "")
  result
}

///|
/// Returns the value at a JSON Pointer path, raising an input error when
/// the path is malformed or absent.
pub fn Value::pointer(self : Value, path : String) -> Value raise {
  at(self, path)
}

///|
/// Canonical JSON text: object keys in UTF-16 code unit order, no
/// whitespace, arrays in order.
pub fn Value::canonical(self : Value) -> String {
  canonical(self)
}
