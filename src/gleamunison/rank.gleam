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

// ── Vector layer: morphological similarity BM25 cannot see ─────────────────
// BM25 needs exact token overlap: "retries" never matches "retry". Char
// trigrams of wrapped words give subword signal ("^re","ret","etr" shared by
// both). Embeddings are sparse hash vectors — deterministic, local, no model
// download. Honest limit: this is *lexical* similarity, not synonymy —
// "backoff" will not match "circuit breaker".

import gleam/dict

const dims = 1024

pub type DocV(a) {
  DocV(id: a, text: String)
}

/// Sparse embedding: dim -> count. 1024 dims is enough that collisions are
/// rare at codebase scale, and collisions are deterministic (same trigram,
/// same dim) so they blur rather than corrupt.
pub type Vector {
  Vector(entries: dict.Dict(Int, Int))
}

@external(erlang, "erlang", "phash2")
fn phash(s: String) -> Int

@external(erlang, "math", "sqrt")
fn sqrt(x: Float) -> Float

fn trigrams(word: String) -> List(String) {
  window3(string.to_graphemes("^" <> word <> "$"))
}

fn window3(gs: List(String)) -> List(String) {
  case gs {
    [a, b, c, ..rest] -> [a <> b <> c, ..window3([b, c, ..rest])]
    _ -> []
  }
}

pub fn embed(text: String) -> Vector {
  tokenize(text)
  |> list.flat_map(trigrams)
  |> list.fold(dict.new(), fn(acc, tri) {
    let dim = phash(tri) % dims
    let n = case dict.get(acc, dim) {
      Ok(c) -> c + 1
      Error(_) -> 1
    }
    dict.insert(acc, dim, n)
  })
  |> Vector
}

pub fn cosine(a: Vector, b: Vector) -> Float {
  cosine_shared(a, b).0
}

/// Cosine plus the number of shared trigram dims. One shared trigram is
/// coincidence (word-start "^no" is in both "no" and "not"); two is
/// evidence. Callers use the count as a match gate.
pub fn cosine_shared(a: Vector, b: Vector) -> #(Float, Int) {
  let #(dot, shared) =
    dict.fold(a.entries, #(0, 0), fn(acc, dim, count) {
      case dict.get(b.entries, dim) {
        Ok(bc) -> #(acc.0 + count * bc, acc.1 + 1)
        Error(_) -> acc
      }
    })
  let mag = fn(v: Vector) {
    sqrt(int_to_float(dict.fold(v.entries, 0, fn(acc, _, c) { acc + c * c })))
  }
  let denom = mag(a) *. mag(b)
  let score = case denom >. 0.0 {
    True -> int_to_float(dot) /. denom
    False -> 0.0
  }
  #(score, shared)
}

fn normalize(scores: List(#(Float, a))) -> List(#(Float, a)) {
  let max =
    list.fold(scores, 0.0, fn(acc, pair) {
      case pair.0 >. acc {
        True -> pair.0
        False -> acc
      }
    })
  case max >. 0.0 {
    False -> scores
    True -> list.map(scores, fn(pair) { #(pair.0 /. max, pair.1) })
  }
}

/// Hybrid rank: normalized BM25 (exact token relevance) + normalized cosine
/// over trigram embeddings (subword/morphological similarity). One sum, no
/// knobs. Zero-score docs dropped; descending.
pub fn rank_hybrid(query: String, docs: List(DocV(a))) -> List(#(Float, a)) {
  case docs == [] || tokenize(query) == [] {
    True -> []
    False -> {
      let bm25 =
        rank(
          query,
          list.map(docs, fn(d) { Doc(id: d.id, tokens: tokenize(d.text)) }),
        )
        |> normalize
      let qv = embed(query)
      // Two gates on the vector path, both documented by tests:
      // 1. shared >= 2: one shared trigram is coincidence ("no"~"not"),
      //    two is evidence ("retries"~"retry" share ^re/ret/etr).
      // 2. cosine > max(0.1, 0.5*max_cosine): trace cutoff plus drop
      //    stragglers far below the best hit. A miss returns [].
      let cosines =
        list.map(docs, fn(d) { #(cosine_shared(qv, embed(d.text)), d.id) })
      let max_cos =
        list.fold(cosines, 0.0, fn(acc, p) {
          case p.0.0 >. acc {
            True -> p.0.0
            False -> acc
          }
        })
      let floor = case 0.5 *. max_cos >. 0.1 {
        True -> 0.5 *. max_cos
        False -> 0.1
      }
      docs
      |> list.filter_map(fn(d) {
        let b = case list.find(bm25, fn(p) { p.1 == d.id }) {
          Ok(p) -> p.0
          Error(_) -> 0.0
        }
        let #(c, shared) = case list.find(cosines, fn(p) { p.1 == d.id }) {
          Ok(p) -> p.0
          Error(_) -> #(0.0, 0)
        }
        let s = case c >. floor && shared >= 2 {
          True -> b +. c
          False -> b
        }
        case s >. 0.0 {
          True -> Ok(#(s, d.id))
          False -> Error(Nil)
        }
      })
      |> list.sort(fn(a, b) { float.compare(b.0, a.0) })
    }
  }
}
