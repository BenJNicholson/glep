//// Module defining a Regex type representing the abstract syntax of a regular
//// expression, along with constructor functions and a derivative function.

import gleam/list
import gleam/order.{type Order}
import gleam/set.{type Set}
import gleam/string

/// Type representing a regular expression
pub opaque type Regex {
  EmptySet
  Epsilon
  CharacterSet(chars: Set(String))
  Any
  Concatenation(List(Regex))
  Star(Regex)
  Or(List(Regex))
  And(List(Regex))
  Complement(Regex)
}

/// Generic function for lexicographically comparing lists given a comparison
/// function.
fn compare_list(l1: List(t), l2: List(t), comparer: fn(t, t) -> Order) -> Order {
  case l1, l2 {
    [], [] -> order.Eq
    [], _ -> order.Lt
    _, [] -> order.Gt
    [h1, ..t1], [h2, ..t2] ->
      case comparer(h1, h2) {
        order.Gt -> order.Gt
        order.Lt -> order.Lt
        order.Eq -> compare_list(t1, t2, comparer)
      }
  }
}

/// Compares regexes according to rules used by ml-ulex
pub fn compare(re1: Regex, re2: Regex) -> order.Order {
  case re1, re2 {
    // Equal if they're the same
    r, s if r == s -> order.Eq
    //---- Compare primitive values ----
    // Empty string
    Epsilon, _ -> order.Lt
    _, Epsilon -> order.Gt
    // Any
    Any, _ -> order.Lt
    _, Any -> order.Gt
    // Empty set
    EmptySet, _ -> order.Lt
    _, EmptySet -> order.Gt
    // Compare character sets by lexicographic order of their elements
    CharacterSet(s1), CharacterSet(s2) ->
      string.compare(
        s1 |> set.to_list |> string.concat,
        s2 |> set.to_list |> string.concat,
      )
    CharacterSet(_), _ -> order.Lt
    _, CharacterSet(_) -> order.Gt
    //---- Compare combinations of regexes ----
    // Compare concatenations
    Concatenation(res1), Concatenation(res2) ->
      compare_list(res1, res2, compare)
    Concatenation(_), _ -> order.Lt
    _, Concatenation(_) -> order.Gt
    // Compare stars
    Star(re1), Star(re2) -> compare(re1, re2)
    Star(_), _ -> order.Lt
    _, Star(_) -> order.Gt
    // Compare logical operations
    Or(res1), Or(res2) -> compare_list(res1, res2, compare)
    Or(_), _ -> order.Lt
    _, Or(_) -> order.Gt
    And(res1), And(res2) -> compare_list(res1, res2, compare)
    And(_), _ -> order.Lt
    _, And(_) -> order.Gt
    // Compare complements
    Complement(re1), Complement(re2) -> compare(re1, re2)
  }
}

// Constructors ----------------------------------------------------------------

/// Makes a new EmptySet value
pub fn new_empty_set() {
  EmptySet
}

/// Makes a new Epsilon value
pub fn new_epsilon() {
  Epsilon
}

/// Makes a new Any value
pub fn new_any() {
  Any
}

/// Makes a new CharacterSet value unless the given set is empty, in which case
/// returns an EmptySet.
pub fn new_character_set(chars: Set(String)) {
  case set.is_empty(chars) {
    True -> EmptySet
    False -> CharacterSet(chars)
  }
}

/// Makes a new Concatenation value given two Regex values
pub fn new_concatenation(r1: Regex, r2: Regex) {
  case r1, r2 {
    Epsilon, r | r, Epsilon -> r
    EmptySet, _ | _, EmptySet -> EmptySet
    Concatenation(res1), Concatenation(res2) ->
      Concatenation(list.append(res1, res2))
    re, Concatenation(res) -> Concatenation([re, ..res])
    Concatenation(res), re -> Concatenation(list.append(res, [re]))
    re1, re2 -> Concatenation([re1, re2])
  }
}

/// Makes a new Concatenation given a list of Regex values
pub fn new_concatenation_from_list(res: List(Regex)) {
  case res {
    [] -> Epsilon
    [re_head, ..re_tail] ->
      new_concatenation(re_head, new_concatenation_from_list(re_tail))
  }
}

/// Makes a new Kleene star of the given Regex
pub fn new_star(r: Regex) {
  case r {
    Epsilon -> Epsilon
    EmptySet -> Epsilon
    Star(_) -> r
    a -> Star(a)
  }
}

//---- Helper functions for making Or and And values ----
fn merge(res1, res2) {
  case res1, res2 {
    [], res2 -> res2
    res1, [] -> res1
    [r1, ..r1_tail], [r2, ..r2_tail] -> {
      case compare(r1, r2) {
        order.Lt -> [r1, ..merge(r1_tail, res2)]
        order.Eq -> merge(res1, r2_tail)
        order.Gt -> [r2, ..merge(res1, r2_tail)]
      }
    }
  }
}

fn wrap(re1, re2, op) {
  let assert CharacterSet(chars1) = re1 as "Error: Must be a CharacterSet"
  let assert CharacterSet(chars2) = re2 as "Error: Must be a CharacterSet"
  new_character_set(op(chars1, chars2))
}

fn re_insert(charset: Regex, res: List(Regex)) -> List(Regex) {
  case charset, res {
    cs, [] -> [cs]
    cs, [re1, ..re_tail] ->
      case compare(cs, re1) {
        order.Lt -> [charset, ..res]
        order.Eq -> panic as "Error: Should be only one CharacterSet"
        order.Gt -> [re1, ..re_insert(cs, re_tail)]
      }
  }
}

fn merge_with_character_sets(res, op) {
  let #(char_sets, other_res) =
    list.partition(res, fn(re) {
      case re {
        CharacterSet(_) -> True
        _ -> False
      }
    })
  case char_sets {
    [] -> res
    [_] -> res
    [charset1, ..charset_tail] -> {
      let merged =
        list.fold(charset_tail, charset1, fn(a, b) { wrap(a, b, op) })
      re_insert(merged, other_res)
    }
  }
}

/// Makes an Or given two Regex values
pub fn new_or(re1: Regex, re2: Regex) {
  let mk = fn(a, b) {
    case merge_with_character_sets(merge(a, b), set.union) {
      [] -> EmptySet
      [r] -> r
      res -> Or(res)
    }
  }
  case re1, re2 {
    EmptySet, _ -> re2
    _, EmptySet -> re1
    CharacterSet(s1), CharacterSet(s2) -> new_character_set(set.union(s1, s2))
    Or(res1), Or(res2) -> mk(res1, res2)
    Or(res1), _ -> mk(res1, [re2])
    _, Or(res2) -> mk([re1], res2)
    re1, re2 ->
      case compare(re1, re2) {
        order.Lt -> Or([re1, re2])
        order.Eq -> re1
        order.Gt -> Or([re2, re1])
      }
  }
}

/// Makes an And given two Regex values
pub fn new_and(re1: Regex, re2: Regex) {
  let mk = fn(a, b) {
    case merge_with_character_sets(merge(a, b), set.intersection) {
      [] -> EmptySet
      [re] -> re
      res -> And(res)
    }
  }
  case re1, re2 {
    EmptySet, _ -> re2
    _, EmptySet -> re1
    CharacterSet(s1), CharacterSet(s2) ->
      new_character_set(set.intersection(s1, s2))
    And(res1), And(res2) -> mk(res1, res2)
    And(res1), _ -> mk(res1, [re2])
    _, And(res2) -> mk([re1], res2)
    re1, re2 ->
      case compare(re1, re2) {
        order.Lt -> And([re1, re2])
        order.Eq -> re1
        order.Gt -> And([re2, re1])
      }
  }
}

/// Makes a Complement of the given Regex
pub fn new_complement(r: Regex) {
  case r {
    Complement(re) -> re
    EmptySet -> new_star(Any)
    re -> Complement(re)
  }
}

// Convenience functions for common regex shorthands ---------------------

/// Implements the ? operator
pub fn new_zero_or_one(re: Regex) {
  new_or(Epsilon, re)
}

fn low(re: Regex, n: Int) {
  case n {
    0 -> Epsilon
    1 -> re
    n -> new_concatenation(re, low(re, n - 1))
  }
}

fn high(re: Regex, n: Int) {
  case n {
    0 -> Epsilon
    1 -> new_zero_or_one(re)
    n -> new_concatenation(new_zero_or_one(re), high(re, n - 1))
  }
}

/// Implements [re]{min, max} syntax
pub fn new_repeat(re: Regex, min: Int, max: Int) {
  assert min < max as "Error: Minimum repetitions must be less than maximum"
  new_concatenation(low(re, min), high(re, max))
}

/// Implements [re]{n} syntax
pub fn new_exactly(re: Regex, n: Int) {
  case n {
    0 -> Epsilon
    n -> new_concatenation_from_list(list.repeat(re, n))
  }
}

/// Implements [re]{min,} syntax
pub fn new_at_least(re: Regex, n: Int) {
  case n {
    0 -> new_star(re)
    n -> new_concatenation(re, new_at_least(re, n - 1))
  }
}

/// Implements + operator
pub fn new_one_or_more(re: Regex) {
  new_at_least(re, 1)
}

// Derivatives -----------------------------------------------------------------
/// Checks Regex nullability, i.e. whether the empty string Epsilon is in the
/// language recognized by the regular expression.
fn is_nullable(regex re: Regex) -> Bool {
  case re {
    EmptySet -> False
    CharacterSet(_) -> False
    Any -> False
    Epsilon -> True
    Concatenation(res) -> res |> list.all(is_nullable)
    Star(_) -> True
    Or(res) -> res |> list.any(is_nullable)
    And(res) -> res |> list.all(is_nullable)
    Complement(re) -> !is_nullable(re)
  }
}

/// Converts nullability boolean to Regex value.
fn nu(regex re: Regex) -> Regex {
  case is_nullable(re) {
    True -> Epsilon
    False -> EmptySet
  }
}

/// Takes the derivative of a Regex with respect to the given character. The
/// argument `a` must be a single character.
pub fn derivative(re: Regex, a: String) -> Regex {
  case re {
    Epsilon -> EmptySet
    CharacterSet(s) ->
      case set.contains(s, a) {
        True -> Epsilon
        False -> EmptySet
      }
    EmptySet -> EmptySet
    Any -> Epsilon
    Concatenation([]) -> EmptySet
    Concatenation([r]) -> derivative(r, a)
    Concatenation([r, ..res]) ->
      new_or(
        new_concatenation_from_list([derivative(r, a), ..res]),
        new_concatenation(
          nu(r),
          derivative(new_concatenation_from_list(res), a),
        ),
      )
    Complement(expr1) -> new_complement(derivative(expr1, a))
    Star(expr1) -> new_concatenation(derivative(expr1, a), new_star(expr1))
    Or([r]) -> derivative(r, a)
    Or(rs) -> {
      let assert [r, ..res] = rs as "Error: OR with zero operands"
      new_or(derivative(r, a), derivative(Or(res), a))
    }
    And([r]) -> derivative(r, a)
    And(rs) -> {
      let assert [r, ..res] = rs as "Error: AND with zero operands"
      new_and(derivative(r, a), derivative(And(res), a))
    }
  }
}

/// Iteratively takes the derivative of a Regex with respect to a string of
/// arbitrary length.
pub fn string_derivative(regex re: Regex, with_respect_to wrt: String) {
  case string.pop_grapheme(wrt) {
    Error(Nil) -> re
    Ok(#(a, rest)) -> derivative(string_derivative(re, rest), a)
  }
}
