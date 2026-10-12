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
