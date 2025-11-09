import gleam/string
import regex.{type Regex}

pub const digits = "0123456789"

pub const word_characters = digits
  <> "abcdefghijklmnopqrstuvwxyz"
  <> "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  <> "_"

pub fn parse_pattern(pattern: String) -> Regex {
  todo
}
