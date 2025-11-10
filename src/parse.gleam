import gleam/list
import gleam/string
import regex.{type Regex}

pub const digits = "0123456789"

pub const word_characters = digits
  <> "abcdefghijklmnopqrstuvwxyz"
  <> "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  <> "_"

pub const metacharacters = "\\[]{}().$^*+?|"

pub type ParseError {
  EscapedOrdinaryCharacter(String, position: Int)
  UnbalancedParenthesis(position: Int)
  UnbalancedBracket(position: Int)
  UnbalancedBrace(position: Int)
  EmptyParenthesizedExpression(position: Int)
  DisallowedFirstCharacter(String, position: Int)
  DisallowedLastCharacter(String, position: Int)
  DisallowedCharacterSequence(String, String, position: Int)
  ExpectedInteger(position: Int)
  EndOfPattern
}

// Precedence (high to low), POSIX ERE Standard:
// - collation-related bracket symbols: [= =] [: :] [. .]
// - escaped characters:                \<special character>
// - bracket expression:                []
// - grouping:                          ()
// - single-character ERE duplication:  * + ? {m,n}
// - concatenation:                     <no operator>
// - anchoring:                         ^ $
// - alternation:                       |

// ---- Extended regular expression grammar ----
// Tokens:
// ORD_CHAR QUOTED_CHAR DUP_COUNT
//
// ere :
//     | ere_branch
//     | ere '|' ere_branch
// ere_branch :
//     | ere_expression
//     | ere_branch ere_expression
// ere_expression :
//     | one_char_or_coll_elem_ere
//     | '^'
//     | '$'
//     | '(' ere ')'
//     | ere_expression ere_dupl_symbol
// one_char_or_coll_elem_ere :
//     | ORD_CHAR
//     | QUOTED_CHAR
//     | '.'
//     | bracket_expression
// ere_dupl_symbol :
//     | '*'
//     | '+'
//     | '{' DUP_COUNT '}'
//     | '{' DUP_COUNT ',' '}'
//     | '{' DUP_COUNT ',' DUP_COUNT '}'

type Token {
  Character(String)
  Period
  BracketExpression(String)
  LeftParen
  RightParen
  AnchorSymbol(Anchor)
  Op(Operator)
}

type Operator {
  DuplicationSymbol(Duplication)
  VerticalBar
}

type Duplication {
  Asterisk
  PlusSign
  QuestionMark
  Exactly(Int)
  Between(min: Int, max: Int)
  AtLeast(Int)
}

type Anchor {
  Caret
  DollarSign
}

/// This function must not be used within a bracket expression
fn is_ere_special_character(character: String) {
  string.contains(".[]\\(){}*+?|^$", character)
}

// Precedence (high to low), POSIX ERE Standard:
// - collation-related bracket symbols: [= =] [: :] [. .]
// - escaped characters:                \<special character>
// - bracket expression:                []
// - grouping:                          ()
// - single-character ERE duplication:  * + ? {m,n}
// - concatenation:                     <no operator>
// - anchoring:                         ^ $
// - alternation:                       |

fn tokenize_bracket_expr(
  pattern: String,
  index: Int,
) -> #(Result(Token, ParseError), String) {
  let #(prefix, remainder) = case pattern {
    "]" <> rest -> #("]", rest)
    "^]" <> rest -> #("^]", rest)
    _ -> #("", pattern)
  }
  case string.split_once(remainder, "]") {
    Ok(#(s, rest)) -> #(Ok(BracketExpression(prefix <> s)), rest)
    Error(Nil) -> #(Error(UnbalancedBracket(index)), pattern)
  }
}

fn tokenize_escaped_char(
  pattern: String,
  index: Int,
) -> #(Result(Token, ParseError), String) {
  case string.pop_grapheme(pattern) {
    Ok(#(c, rest)) ->
      case is_ere_special_character(c) {
        True -> #(Ok(Character(c)), rest)
        False -> #(Error(EscapedOrdinaryCharacter(c, index)), rest)
      }
    Error(Nil) -> #(Error(DisallowedLastCharacter("\\", index)), pattern)
  }
}

fn tokenize_range(
  pattern: String,
  index: Int,
) -> #(Result(Token, ParseError), String) {
  todo
}

fn tokenize_ere(
  pattern: String,
  index: Int,
  tokens: List(Result(Token, ParseError)),
) -> List(Result(Token, ParseError)) {
  let #(next_token, remaining_pattern) = case string.pop_grapheme(pattern) {
    Ok(#(c, rest)) ->
      case c {
        "\\" -> tokenize_escaped_char(rest, index)
        "." -> #(Ok(Period), rest)
        "[" -> tokenize_bracket_expr(rest, index)
        "(" -> #(Ok(LeftParen), rest)
        ")" -> #(Ok(RightParen), rest)
        "{" -> tokenize_range(rest, index)
        "*" -> #(Ok(Op(DuplicationSymbol(Asterisk))), rest)
        "+" -> #(Ok(Op(DuplicationSymbol(PlusSign))), rest)
        "?" -> #(Ok(Op(DuplicationSymbol(QuestionMark))), rest)
        "^" -> #(Ok(AnchorSymbol(Caret)), rest)
        "$" -> #(Ok(AnchorSymbol(DollarSign)), rest)
        "|" -> #(Ok(Op(VerticalBar)), rest)
        _ -> #(Ok(Character(c)), rest)
      }
    Error(Nil) -> #(Error(EndOfPattern), "")
  }
  case next_token {
    Error(EndOfPattern) -> tokens |> list.reverse
    Error(e) -> [Error(e)]
    _ -> tokenize_ere(remaining_pattern, index + 1, [next_token, ..tokens])
  }
}

// ---- Bracket Expression Grammar ----
// Tokens:
// COLL_ELEM_SINGLE COL_ELEM_MULTI META_CHAR
//
// Open_equal:  '[='
// Equal_close: '=]'
// Open_dot:    '[.'
// Dot_close:   '.]'
// Open_colon:  '[:'
// Colon_close  ':]'
// 
// class_name: a keyword to the LC_CTYPE locale category (representing a character
// class) in the current locale and is only recognized between [: and :]
//
// bracket_expression :
//     | '[' matching_list ']'
//     | '[' nonmatching_list']'
// matching_list :
//     | bracket_list
// nonmatching_list :
//     | '^' bracket_list
// bracket_list :
//     | follow_list
//     | follow_list '-'
// follow_list :
//     | expression_term
//     | follow_list expression_term
// expression_term :
//     | single_expression
//     | range_expression
// single_expression :
//     | end_range
//     | character_class
//     | equivalence_class
// range_expression :
//     | start_range end_range
//     | start_range '-'
// start_range :
//     | end_range '-'
// end_range :
//     | COLL_ELEM_SINGLE
//     | collating_symbol
// collating_symbol :
//     | Open_dot COLL_ELEM_SINGLE Dot_close
//     | Open_dot COLL_ELEM_MULTI Dot_close
//     | Open_dot META_CHAR Dot_close
// equivalence_class : 
//     | Open_equal COLL_ELEM_SINGLE Equal_close
//     | Open_equal COLL_ELEM_MULTI Equal_close
// character_class :
//     | Open_colon class_name Colon_close

pub fn parse_pattern(pattern: String) -> Result(Regex, ParseError) {
  let tokens = tokenize_ere(pattern, 0, [])
  todo
}

fn parse_escape(pattern: String) -> Result(Regex, ParseError) {
  todo
}

fn parse_bracket(pattern: String) -> Result(Regex, ParseError) {
  todo
}

fn parse_parenthesis(pattern: String) -> Result(Regex, ParseError) {
  todo
}

fn parse_quantifier(pattern: String) -> Result(Regex, ParseError) {
  todo
}
