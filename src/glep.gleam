import argv
import gleam/io
import input

@external(erlang, "erlang", "halt")
pub fn exit(code: Int) -> Int

fn match_pattern(input: String, pattern: String) -> Result(Bool, String) {
  todo
}

pub fn main() -> Int {
  let args = argv.load().arguments
  let assert Ok(input_line) = input.input("")

  case args {
    ["-E", pattern, ..] -> {
      case match_pattern(input_line, pattern) {
        Ok(True) -> exit(0)
        Ok(False) -> exit(1)
        Error(e) -> {
          echo e
          exit(2)
        }
      }
    }
    _ -> {
      io.println("Expected first argument to be '-E'")
      exit(1)
    }
  }

  exit(0)
}
