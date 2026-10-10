import gleam/list
import gleam/string
import gleamunison/codebase
import gleamunison/prompt

pub fn put_then_get_roundtrip_test() {
  let cb = codebase.empty()
  let #(cb, ref) = prompt.put(cb, "You are a helpful assistant.")
  let assert Ok(got) = prompt.get(cb, ref)
  let assert True = got == "You are a helpful assistant."
}

pub fn same_template_same_hash_test() {
  let cb = codebase.empty()
  let #(cb, ref1) = prompt.put(cb, "Summarize {{topic}}")
  let #(_cb, ref2) = prompt.put(cb, "Summarize {{topic}}")
  let assert True = ref1 == ref2
}

pub fn different_templates_different_hashes_test() {
  let cb = codebase.empty()
  let #(cb, ref1) = prompt.put(cb, "Summarize {{topic}}")
  let #(_cb, ref2) = prompt.put(cb, "Translate {{topic}}")
  let assert False = ref1 == ref2
}

pub fn hash_is_the_audit_identity_test() {
  let cb = codebase.empty()
  let #(_cb, ref) = prompt.put(cb, "Hello")
  // identity is the content hash itself, displayable for traces
  let assert True = string.length(prompt.ref_hex(ref)) == 64
}

pub fn render_by_hash_substitutes_vars_test() {
  let cb = codebase.empty()
  let #(cb, ref) = prompt.put(cb, "Summarize {{topic}} in {{style}} style.")
  let assert Ok(rendered) =
    prompt.render_by_hash(cb, ref, [#("topic", "effects"), #("style", "haiku")])
  let assert True = rendered == "Summarize effects in haiku style."
}

pub fn render_missing_var_names_it_test() {
  let cb = codebase.empty()
  let #(cb, ref) = prompt.put(cb, "Summarize {{topic}}")
  let assert Error(prompt.MissingVar(name)) = prompt.render_by_hash(cb, ref, [])
  let assert True = name == "topic"
}

pub fn render_does_not_html_escape_test() {
  let cb = codebase.empty()
  let #(cb, ref) = prompt.put(cb, "Input: {{payload}}")
  let assert Ok(rendered) =
    prompt.render_by_hash(cb, ref, [#("payload", "<b>bold</b>")])
  let assert True = rendered == "Input: <b>bold</b>"
}

pub fn get_unknown_ref_is_not_found_test() {
  let cb = codebase.empty()
  let #(_cb, ref) = prompt.put(codebase.empty(), "elsewhere")
  let assert Error(prompt.NotFound) = prompt.get(cb, ref)
}

pub fn put_joins_the_dag_test() {
  let cb = codebase.empty()
  let #(cb, ref) = prompt.put(cb, "in the dag")
  let assert True = list.contains(codebase.list_refs(cb), ref)
}

pub fn vars_extraction_dedups_test() {
  let vs = prompt.vars("{{a}} and {{b}} and {{a}} again")
  let assert True = list.contains(vs, "a")
  let assert True = list.contains(vs, "b")
  let assert True = list.length(vs) == 2
}
