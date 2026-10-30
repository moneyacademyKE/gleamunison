import gleam/dict
import gleam/list
import gleamunison/bootstraps
import gleamunison/codebase
import gleamunison/definition_codec as codec
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{Ref}
import gleamunison/parser
import gleamunison/publication
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/test_runner
import gleamunison/types.{CTTerm, empty_cache}
import gleamunison/verify
import gleeunit/should

fn boot() {
  repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
}

fn definition(name: String, source: String) {
  let #(cache, defs) = boot()
  let assert Ok(surface) = parser.parse_string(source)
  let all_defs = [#(name, SurfaceTermDef(surface)), ..defs]
  let assert Ok(definition) =
    test_runner.elaborated_def_for(name, all_defs, cache)
  #(all_defs, cache, definition)
}

fn assert_storable(definition) {
  let bytes = codec.encode(definition)
  let assert Ok(_) = codec.decode(bytes)
  storage.verify_content(Ref(codebase.hash_of_definition(definition)), bytes)
  |> should.equal(Ok(Nil))
}

pub fn builtin_identity_dict_keys_roundtrips_cas_test() {
  let #(_, _, definition) = definition("keys-of", "(lam d (dict-keys d))")
  assert_storable(definition)
}

pub fn builtin_identity_json_roundtrips_cas_test() {
  let #(_, _, definition) = definition("parse-json", "(lam s (json-parse s))")
  assert_storable(definition)
}

pub fn builtin_identity_file_read_requires_io_evidence_test() {
  let #(defs, cache, _) = definition("reader", "(lam p (file-read p))")
  let assert Ok([#("reader", _, effectful)]) =
    publication.hash_defs(["reader"], defs, cache)
  effectful |> should.be_true
}

pub fn builtin_identity_http_get_requires_io_evidence_test() {
  let #(defs, cache, _) = definition("fetcher", "(lam url (http-get url))")
  let assert Ok([#("fetcher", _, effectful)]) =
    publication.hash_defs(["fetcher"], defs, cache)
  effectful |> should.be_true
}

pub fn builtin_identity_every_bootstrap_term_has_its_declared_type_test() {
  let #(cache, _) = boot()
  list.each(bootstraps.get_init_defs_data(), fn(entry) {
    case entry {
      bootstraps.BTerm(name, _, declared) -> {
        let assert Ok(CTTerm(actual)) =
          dict.get(cache.entries, repl_eval.ref_for_name(name))
        actual |> should.equal(declared)
      }
      _ -> Nil
    }
  })
}
