///|
extern "js" fn read_input(path : String) -> String =
  #| (path) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   const bytes = fs.readFileSync(path === '-' ? 0 : path);
  #|   if (bytes.length > 16777216) throw new Error('input exceeds 16 MiB');
  #|   return new TextDecoder('utf-8', {fatal:true}).decode(bytes);
  #| }

///|
extern "js" fn status(code : Int32) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
fn main {
  let args = @env.args()
  if args.length() != 3 {
    println(
      "Usage: moon run cmd/main --target js -- request.json (or - for stdin)",
    )
    status(2)
  } else {
    try {
      let input = @json.parse(read_input(args[2]))
      let output = @engine.execute(input)
      println(output.stringify(indent=2))
      // Exit codes: 0 valid report, 1 rejected request, 2 report with issues.
      match output {
        Json::Object(fields) =>
          match fields.get("valid") {
            Some(Json::False) => status(2)
            _ => ()
          }
        _ => ()
      }
    } catch {
      error => {
        println(
          Json::object({ "error": Json::string(error.to_string()) }).stringify(),
        )
        status(1)
      }
    }
  }
}
