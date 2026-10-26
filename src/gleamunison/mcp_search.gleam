//// Search over one visible definition catalog, with identity and origin intact.

import gleam/bit_array
import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleamunison/agent_read_model.{type Entry}
import gleamunison/codebase_index
import gleamunison/elab_types.{type SurfaceDef, SurfaceTermDef}
import gleamunison/mcp
import gleamunison/mcp_definition
import gleamunison/rank
import gleamunison/types.{type TypeCache}

pub type SearchHit {
  SearchHit(
    name: String,
    kind: String,
    ref_hex: String,
    content_ref_hex: Option(String),
    origin: String,
    branch: Option(String),
    score: Float,
  )
}

pub fn hits_json(hits: List(SearchHit)) -> String {
  let parts =
    list.map(hits, fn(hit) {
      "{\"name\":"
      <> mcp.json_string(hit.name)
      <> ",\"kind\":"
      <> mcp.json_string(hit.kind)
      <> ",\"ref\":"
      <> mcp_definition.nullable_json_string(hit.content_ref_hex)
      <> ",\"name_ref\":"
      <> mcp.json_string(hit.ref_hex)
      <> ",\"origin\":"
      <> mcp.json_string(hit.origin)
      <> ",\"branch\":"
      <> mcp_definition.nullable_json_string(hit.branch)
      <> ",\"score\":"
      <> float.to_string(hit.score)
      <> "}"
    })
  "[" <> string.join(parts, ",") <> "]"
}

pub fn search(
  cache: TypeCache,
  defs: List(#(String, SurfaceDef)),
  entries: List(Entry),
  query: String,
) -> List(SearchHit) {
  let scored =
    rank.rank_hybrid(
      query,
      list.map(entries, fn(entry) {
        let name = agent_read_model.name(entry)
        let body = case entry {
          agent_read_model.Source(definition:, ..) -> body_tokens(definition)
          agent_read_model.Stored(..) -> []
        }
        rank.DocV(
          id: entry,
          text: name <> " " <> name <> " " <> string.join(body, " "),
        )
      }),
    )
  let sorted =
    list.sort(scored, fn(a, b) {
      case float.compare(b.0, a.0) {
        order.Eq ->
          string.compare(agent_read_model.name(a.1), agent_read_model.name(b.1))
        other -> other
      }
    })
  list.map(sorted, fn(pair) {
    let entry = pair.1
    let #(origin, branch) = case agent_read_model.origin(entry) {
      agent_read_model.Bootstrap -> #("bootstrap", None)
      agent_read_model.Scratch -> #("scratch", None)
      agent_read_model.Branch(name) -> #("branch", Some(name))
    }
    SearchHit(
      name: agent_read_model.name(entry),
      kind: codebase_index.kind_of_entry(entry),
      ref_hex: codebase_index.ref_hex_entry(entry),
      content_ref_hex: mcp_definition.content_hex(cache, defs, entry),
      origin:,
      branch:,
      score: pair.0,
    )
  })
}

/// Search program words, never serialized refs or source spans. Stored terms
/// expose metadata only: no source is invented for body matching.
fn body_tokens(def: SurfaceDef) -> List(String) {
  case def {
    SurfaceTermDef(term) -> term_tokens(term)
    _ -> []
  }
}

fn term_tokens(term: elab_types.SurfaceTerm) -> List(String) {
  case term {
    elab_types.SLoc(inner, _) -> term_tokens(inner)
    elab_types.SVar(name) -> rank.tokenize(name)
    elab_types.SText(bytes) ->
      case bit_array.to_string(bytes) {
        Ok(text) -> rank.tokenize(text)
        Error(_) -> []
      }
    elab_types.SApply(function, argument) ->
      list.append(term_tokens(function), term_tokens(argument))
    elab_types.SLambda(param, body) ->
      list.append(rank.tokenize(param), term_tokens(body))
    elab_types.SLet(name, value, body) ->
      list.append(
        rank.tokenize(name),
        list.append(term_tokens(value), term_tokens(body)),
      )
    elab_types.SMatch(scrutinee, cases) ->
      list.append(
        term_tokens(scrutinee),
        list.flat_map(cases, fn(case_) { term_tokens(case_.body) }),
      )
    elab_types.SDo(ability, operation, args) ->
      list.append(
        rank.tokenize(ability),
        list.append(rank.tokenize(operation), list.flat_map(args, term_tokens)),
      )
    elab_types.SConstruct(name, args) ->
      list.append(rank.tokenize(name), list.flat_map(args, term_tokens))
    elab_types.SHandle(computation, handler, ability) ->
      list.append(
        term_tokens(computation),
        list.append(term_tokens(handler), rank.tokenize(ability)),
      )
    elab_types.SLabeledFn(params, body) ->
      list.append(
        list.flat_map(params, fn(param) {
          list.append(rank.tokenize(param.0), term_tokens(param.1))
        }),
        term_tokens(body),
      )
    elab_types.SUse(binder, call, body) ->
      list.append(
        rank.tokenize(binder),
        list.append(term_tokens(call), term_tokens(body)),
      )
    elab_types.SList(items) -> list.flat_map(items, term_tokens)
    _ -> []
  }
}
