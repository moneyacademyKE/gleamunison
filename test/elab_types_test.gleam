import gleam/list
import gleam/string
import gleamunison/elab_types
import gleamunison/test_runner
import gleamunison/types.{empty_cache}
import gleeunit/should

pub fn describe_name_not_found_test() {
  elab_types.describe(elab_types.NameNotFound("missing_thing"))
  |> should.equal("no definition found for missing_thing")
}

pub fn describe_unknown_operation_test() {
  elab_types.describe(elab_types.UnknownOperation(
    ability: "IO",
    op: "printLine",
  ))
  |> should.equal("unknown operation printLine of ability IO")
}

pub fn describe_missing_ability_decl_test() {
  elab_types.describe(elab_types.MissingAbilityDecl("Store"))
  |> should.equal("no declaration for ability Store")
}

pub fn describe_infer_failed_test() {
  elab_types.describe(elab_types.InferFailed("bad unification"))
  |> should.equal("type inference failed: bad unification")
}

pub fn describe_unsupported_type_ref_test() {
  elab_types.describe(elab_types.UnsupportedTypeRef("List[Int]"))
  |> should.equal("unsupported type reference: List[Int]")
}

pub fn describe_at_wraps_inner_with_span_test() {
  elab_types.describe(elab_types.At(
    elab_types.NameNotFound("missing_thing"),
    elab_types.Span(3, 7),
  ))
  |> should.equal("no definition found for missing_thing at line 3, col 7")
}

pub fn describe_at_nests_test() {
  elab_types.describe(elab_types.At(
    elab_types.At(elab_types.InferFailed("bad"), elab_types.Span(1, 2)),
    elab_types.Span(3, 4),
  ))
  |> should.equal(
    "type inference failed: bad at line 1, col 2 at line 3, col 4",
  )
}

pub fn elaborated_def_for_broken_def_yields_sentence_test() {
  let defs = [
    #("answer", elab_types.SurfaceTermDef(elab_types.SVar("missing_thing"))),
  ]
  let assert Error(sentence) =
    test_runner.elaborated_def_for("answer", defs, empty_cache())
  sentence
  |> string.contains("no definition found for missing_thing")
  |> should.be_true
  // The debug rendering is gone: no constructor dump reaches the user.
  list.any(["NameNotFound(", "InferFailed(", "UnknownOperation("], fn(dump) {
    string.contains(sentence, dump)
  })
  |> should.be_false
}
