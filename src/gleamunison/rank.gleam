//// BM25 ranking over tokenized documents: pure data in, ranked data out.
//// Used by `find` and the MCP search tool. Intentionally standalone from
//// the datalog engine's own in-DB BM25: the CLI path must not transact a
//// database to answer one query.

import gleam/float
import gleam/list
import gleam/string

@external(erlang, "math", "log")
fn ln(x: Float) -> Float

pub type Doc(a) {
  Doc(id: a, tokens: List(String))
}

pub fn tokenize(text: String) -> List(String) {
  text
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(g) {
    case is_alnum(g) {
      True -> g
      False -> " "
    }
  })
  |> string.concat
  |> string.split(" ")
  |> list.filter(fn(w) { w != "" })
}

fn is_alnum(g: String) -> Bool {
  case g {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9" -> True
    _ -> False
  }
}

fn tf(term: String, doc: List(String)) -> Int {
  list.fold(doc, 0, fn(acc, w) {
    case w == term {
      True -> acc + 1
      False -> acc
    }
  })
}

fn df(term: String, docs: List(List(String))) -> Int {
  list.fold(docs, 0, fn(acc, doc) {
    case tf(term, doc) > 0 {
      True -> acc + 1
      False -> acc
    }
  })
}

fn idf(term: String, docs: List(List(String))) -> Float {
  let n = int_to_float(list.length(docs))
  let d = int_to_float(df(term, docs))
  ln({ n -. d +. 0.5 } /. { d +. 0.5 } +. 1.0)
}

fn int_to_float(i: Int) -> Float {
  int_to_float_(i)
}

@external(erlang, "erlang", "float")
fn int_to_float_(i: Int) -> Float

fn score_term(
  term: String,
  doc: List(String),
  idf: Float,
  avgdl: Float,
) -> Float {
  let t = int_to_float(tf(term, doc))
  case t >. 0.0 {
    False -> 0.0
    True -> {
      let k1 = 1.2
      let b = 0.75
      let dl = int_to_float(list.length(doc))
      let denom = t +. k1 *. { 1.0 -. b +. b *. dl /. avgdl }
      idf *. { t *. { k1 +. 1.0 } } /. denom
    }
  }
}

/// Rank docs against a query string. Returns #(score, id) descending,
/// zero-score docs dropped. Empty query or empty corpus yields [].
pub fn rank(query: String, docs: List(Doc(a))) -> List(#(Float, a)) {
  let terms = tokenize(query)
  case terms == [] || docs == [] {
    True -> []
    False -> {
      let all = list.map(docs, fn(d) { d.tokens })
      let total = list.fold(all, 0, fn(acc, t) { acc + list.length(t) })
      let avgdl = case list.length(all) {
        0 -> 1.0
        n -> int_to_float(total) /. int_to_float(n)
      }
      docs
      |> list.map(fn(d) {
        let score =
          list.fold(terms, 0.0, fn(acc, term) {
            acc +. score_term(term, d.tokens, idf(term, all), avgdl)
          })
        #(score, d.id)
      })
      |> list.filter(fn(pair) { pair.0 >. 0.0 })
      |> list.sort(fn(a, b) { float.compare(b.0, a.0) })
    }
  }
}
