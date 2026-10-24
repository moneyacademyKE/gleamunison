//// Frozen simple reference: corpus scans and list joins are deliberately slow.

import gleam/float
import gleam/int
import gleam/list
import gleamunison/rank
import gleeunit/should

@external(erlang, "math", "log")
fn ln(value: Float) -> Float

fn naive_rank(query: String, docs: List(rank.Doc(a))) -> List(#(Float, a)) {
  let terms = rank.tokenize(query)
  case terms == [] || docs == [] {
    True -> []
    False -> {
      let size = int.to_float(list.length(docs))
      let total = list.fold(docs, 0, fn(n, d) { n + list.length(d.tokens) })
      let average = int.to_float(total) /. size
      docs
      |> list.map(fn(d) {
        let score =
          list.fold(terms, 0.0, fn(score, term) {
            let frequency =
              list.count(d.tokens, fn(t) { t == term }) |> int.to_float
            let df =
              list.count(docs, fn(d) { list.contains(d.tokens, term) })
              |> int.to_float
            let weight = ln({ size -. df +. 0.5 } /. { df +. 0.5 } +. 1.0)
            let dl = int.to_float(list.length(d.tokens))
            let denom =
              frequency +. 1.2 *. { 1.0 -. 0.75 +. 0.75 *. dl /. average }
            score
            +. case frequency >. 0.0 {
              True -> weight *. { frequency *. { 1.2 +. 1.0 } } /. denom
              False -> 0.0
            }
          })
        #(score, d.id)
      })
      |> list.filter(fn(p) { p.0 >. 0.0 })
      |> list.sort(fn(a, b) { float.compare(b.0, a.0) })
    }
  }
}

fn naive_hybrid(query: String, docs: List(rank.DocV(a))) -> List(#(Float, a)) {
  let bm25 =
    naive_rank(
      query,
      list.map(docs, fn(d) { rank.Doc(d.id, rank.tokenize(d.text)) }),
    )
  let maximum = list.fold(bm25, 0.0, fn(acc, p) { float.max(acc, p.0) })
  let bm25 = list.map(bm25, fn(p) { #(p.0 /. maximum, p.1) })
  let qv = rank.embed(query)
  let cosines =
    list.map(docs, fn(d) { #(rank.cosine_shared(qv, rank.embed(d.text)), d.id) })
  let maximum = list.fold(cosines, 0.0, fn(acc, p) { float.max(acc, p.0.0) })
  let floor = float.max(0.1, maximum *. 0.5)
  docs
  |> list.filter_map(fn(d) {
    let bm = case list.find(bm25, fn(p) { p.1 == d.id }) {
      Ok(p) -> p.0
      Error(_) -> 0.0
    }
    let #(co, shared) = case list.find(cosines, fn(p) { p.1 == d.id }) {
      Ok(p) -> p.0
      Error(_) -> #(0.0, 0)
    }
    let score =
      bm
      +. case co >. floor && shared >= 2 {
        True -> co
        False -> 0.0
      }
    case score >. 0.0 {
      True -> Ok(#(score, d.id))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { float.compare(b.0, a.0) })
}

pub fn bm25_preserves_scores_repeated_terms_empty_docs_and_ties_test() {
  let docs = [
    rank.Doc(1, ["retry", "timeout", "timeout"]),
    rank.Doc(2, []),
    rank.Doc(3, ["retry"]),
    rank.Doc(4, ["retry"]),
    rank.Doc(5, ["zebra"]),
  ]
  list.each(["retry timeout", "retry retry", "missing", ""], fn(query) {
    rank.rank(query, docs) |> should.equal(naive_rank(query, docs))
  })
}

pub fn hybrid_preserves_duplicate_identity_first_join_and_tie_order_test() {
  let docs = [
    rank.DocV("same", "retry"),
    rank.DocV("same", "network timeout retry timeout"),
    rank.DocV("empty", ""),
    rank.DocV("a", "retries network"),
    rank.DocV("tie", "retry"),
  ]
  list.each(["retry timeout", "retries", "retry retry", "zebra"], fn(query) {
    rank.rank_hybrid(query, docs) |> should.equal(naive_hybrid(query, docs))
  })
}
