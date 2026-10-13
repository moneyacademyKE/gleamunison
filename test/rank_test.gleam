import gleam/list
import gleamunison/rank

pub fn tokenize_splits_and_lowercases_test() {
  let toks = rank.tokenize("Parse-JSON v2_payload")
  assert toks == ["parse", "json", "v2", "payload"]
}

pub fn rank_orders_by_relevance_not_substring_test() {
  // Corpus where plain substring search fails the intent: every doc
  // contains "json", but only one is actually about parsing json.
  let docs = [
    rank.Doc(
      id: "json-logo-render",
      tokens: rank.tokenize("render json logo svg"),
    ),
    rank.Doc(id: "json-config", tokens: rank.tokenize("json config file path")),
    rank.Doc(
      id: "parse-json",
      tokens: rank.tokenize("parse json decode json tokens parse value"),
    ),
  ]
  let ranked = rank.rank("parse json", docs)
  let ids = list.map(ranked, fn(pair) { pair.1 })
  assert list.first(ids) == Ok("parse-json")
}

pub fn rank_scores_descending_test() {
  let docs = [
    rank.Doc(id: "a", tokens: ["cat"]),
    rank.Doc(id: "b", tokens: ["cat", "cat", "dog"]),
  ]
  let ranked = rank.rank("cat", docs)
  case ranked {
    [#(s1, _), #(s2, _)] -> {
      assert s1 >. s2
      Nil
    }
    _ -> panic as "expected two hits"
  }
}

pub fn rank_empty_query_yields_nothing_test() {
  let docs = [rank.Doc(id: "a", tokens: ["cat"])]
  assert rank.rank("", docs) == []
}

pub fn rank_no_match_yields_nothing_test() {
  let docs = [rank.Doc(id: "a", tokens: ["cat"])]
  assert rank.rank("zebra", docs) == []
}

pub fn embed_cosine_identical_text_is_one_test() {
  let v = rank.embed("retry with exponential backoff")
  let c = rank.cosine(v, v)
  assert c >. 0.99
}

pub fn embed_cosine_unrelated_is_low_test() {
  let a = rank.embed("retry with exponential backoff")
  let b = rank.embed("render svg logo path")
  let c = rank.cosine(a, b)
  assert c <. 0.3
}

pub fn hybrid_finds_morphological_variant_bm25_misses_test() {
  // BM25 requires exact token overlap: "retries" never matches "retry".
  // Char-trigram embeddings share the subword, so the hybrid ranker
  // surfaces the doc BM25 alone would drop.
  let docs = [
    rank.DocV(id: "retry-logic", text: "exponential backoff retry handler"),
    rank.DocV(id: "svg-render", text: "render svg logo path stroke"),
  ]
  let bm25_only =
    rank.rank("retries", [
      rank.Doc(
        id: "retry-logic",
        tokens: rank.tokenize("exponential backoff retry handler"),
      ),
      rank.Doc(
        id: "svg-render",
        tokens: rank.tokenize("render svg logo path stroke"),
      ),
    ])
  assert bm25_only == []
  let hybrid = rank.rank_hybrid("retries", docs)
  let ids = list.map(hybrid, fn(pair) { pair.1 })
  assert list.first(ids) == Ok("retry-logic")
}

pub fn hybrid_ranks_backoff_query_first_test() {
  let docs = [
    rank.DocV(id: "svg-render", text: "render svg logo path stroke"),
    rank.DocV(id: "retry-logic", text: "exponential backoff retry handler"),
    rank.DocV(id: "http-client", text: "http request headers response"),
  ]
  let hybrid = rank.rank_hybrid("retry with backoff", docs)
  let ids = list.map(hybrid, fn(pair) { pair.1 })
  assert list.first(ids) == Ok("retry-logic")
}

pub fn hybrid_miss_returns_empty_test() {
  // A query with no lexical relation to the corpus must return nothing:
  // without the cosine floor, noise trigrams ranked the whole corpus.
  let docs = [
    rank.DocV(id: "svg-render", text: "render svg logo path stroke"),
    rank.DocV(id: "retry-logic", text: "exponential backoff retry handler"),
  ]
  assert rank.rank_hybrid("zebra quantum entanglement", docs) == []
}
