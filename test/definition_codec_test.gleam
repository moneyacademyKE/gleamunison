import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleamunison/ast
import gleamunison/codebase
import gleamunison/definition_codec as codec
import gleamunison/elab_types.{Span}
import gleamunison/identity.{Local, Ref, hash_bytes}
import gleamunison/repl_eval
import gleamunison/storage
import gleeunit/should

@external(erlang, "gleamunison_cas_test", "invalid_payloads")
fn invalid_payloads() -> List(BitArray)

fn assert_definition(def: ast.Definition) {
  let bytes = codec.encode(def)
  codec.decode(bytes) |> should.equal(Ok(def))
  storage.verify_content(Ref(codebase.hash_of_definition(def)), bytes)
  |> should.equal(Ok(Nil))
}

pub fn every_term_shape_roundtrips_test() {
  let ref = Ref(hash_bytes(<<"definition reference">>))
  let body = ast.Int(42)
  let patterns = [
    ast.PatVar(Local(0)),
    ast.PatInt(-1),
    ast.PatText(<<"text">>),
    ast.PatCons(Local(0), Local(1)),
    ast.PatEmptyList,
    ast.PatAs(Local(0), ast.PatVar(Local(1))),
    ast.PatConstructor(ref, [ast.PatInt(1)]),
  ]
  let cases =
    list.map(patterns, fn(pattern) {
      ast.Case(pattern, Some(ast.GuardTerm(ast.Int(1))), body)
    })
  let terms = [
    ast.RefTo(ref),
    ast.LocalVarRef(Local(0)),
    ast.Int(-42),
    ast.Float(1.5),
    ast.Text(<<"hello">>),
    ast.List([body]),
    ast.Apply(ast.Lambda(Local(0), body), body),
    ast.Lambda(Local(0), ast.LocalVarRef(Local(0))),
    ast.Let(Local(0), body, body),
    ast.Match(body, [ast.Case(ast.PatVar(Local(0)), None, body), ..cases]),
    ast.Do(ref, Local(0), [body]),
    ast.Handle(body, body, ref),
    ast.Construct(ref, [body]),
    ast.Hole,
    ast.Use(Local(0), body, body),
  ]
  list.each(terms, fn(term) {
    assert_definition(ast.TermDef(term, ast.Builtin(ast.IntType)))
  })
}

pub fn every_type_shape_roundtrips_test() {
  let ref = Ref(hash_bytes(<<"type reference">>))
  let types = [
    ast.TypeVar(0),
    ast.AbilityVar(0),
    ast.App(ref, [ast.TypeVar(0)]),
    ast.Fn(
      [ast.TypeVar(0)],
      ast.Builtin(ast.TextType),
      ast.Required([
        ast.Concrete(ast.AbilityRef(ref)),
        ast.ReqVar(0),
      ]),
    ),
    ast.Builtin(ast.IntType),
    ast.Builtin(ast.FloatType),
    ast.Builtin(ast.TextType),
    ast.Builtin(ast.BoolType),
    ast.Builtin(ast.ListType),
    ast.Builtin(ast.HandlerType),
  ]
  list.each(types, fn(typ) { assert_definition(ast.TermDef(ast.Int(1), typ)) })
}

pub fn declarations_roundtrip_test() {
  let ref = Ref(hash_bytes(<<"decl reference">>))
  let type_refs = [
    ast.TypeRefVar(Local(0)),
    ast.TypeCon(ref),
    ast.TypeRefBuiltin(ast.BoolType),
  ]
  let constructors = [ast.Constructor(Local(0), type_refs)]
  assert_definition(
    ast.TypeDef(ast.Structural(Local(0), [Local(0)], constructors)),
  )
  assert_definition(
    ast.TypeDef(ast.Unique(Local(0), "guid", [Local(0)], constructors)),
  )
  assert_definition(
    ast.AbilityDecl(
      ast.AbilityDeclaration(Local(0), [
        ast.Operation(Local(0), type_refs, ast.TypeRefBuiltin(ast.IntType)),
      ]),
    ),
  )
}

pub fn source_spans_do_not_change_wire_bytes_test() {
  let plain = ast.TermDef(ast.Int(1), ast.Builtin(ast.IntType))
  let located =
    ast.TermDef(ast.Located(ast.Int(1), Span(50, 6)), ast.Builtin(ast.IntType))
  codec.encode(located) |> should.equal(codec.encode(plain))
  codec.decode(codec.encode(located)) |> should.equal(Ok(plain))
  codebase.hash_of_definition(located)
  |> should.equal(codebase.hash_of_definition(plain))
}

pub fn requirement_rows_are_canonical_sets_test() {
  let ref = Ref(hash_bytes(<<"ability">>))
  let one = ast.Concrete(ast.AbilityRef(ref))
  let two = ast.ReqVar(2)
  let first =
    ast.TermDef(
      ast.Int(1),
      ast.Fn([], ast.TypeVar(0), ast.Required([one, two])),
    )
  let second =
    ast.TermDef(
      ast.Int(1),
      ast.Fn([], ast.TypeVar(0), ast.Required([two, one, two])),
    )
  codec.encode(first) |> should.equal(codec.encode(second))
  codebase.hash_of_definition(first)
  |> should.equal(codebase.hash_of_definition(second))
  storage.verify_content(
    Ref(codebase.hash_of_definition(first)),
    codec.encode(second),
  )
  |> should.equal(Ok(Nil))
}

pub fn malformed_definition_encodings_fail_closed_test() {
  list.each(invalid_payloads(), fn(bytes) {
    codec.decode(bytes) |> should.be_error
  })
  codec.decode(<<"GUDEF", 1, 131>>) |> should.be_error
  codec.decode(<<"GUDEF", 2, 131, 97, 1>>) |> should.be_error
  codec.decode(<<"display text">>) |> should.be_error
}

pub fn trailing_data_is_not_ignored_test() {
  let def = ast.TermDef(ast.Int(1), ast.Builtin(ast.IntType))
  codec.decode(bit_array.concat([codec.encode(def), <<0>>])) |> should.be_error
}

pub fn excessive_depth_is_rejected_test() {
  let term =
    list.fold(list.repeat(Nil, 100), ast.Int(1), fn(term, _) {
      ast.Lambda(Local(0), term)
    })
  codec.decode(codec.encode(ast.TermDef(term, ast.TypeVar(0))))
  |> should.be_error
}

pub fn excessively_large_payload_is_rejected_test() {
  let bytes = bit_array.concat(list.repeat(<<0>>, 1_048_577))
  storage.verify_content(Ref(hash_bytes(bytes)), bytes) |> should.be_error
}

pub fn malformed_types_cannot_hide_behind_ignored_fields_test() {
  let malformed =
    bit_array.concat([
      <<"GUDEF", 1>>,
      repl_eval.serialize_term(#("not a definition", 42)),
    ])
  codec.decode(malformed) |> should.be_error
}

pub fn integrity_check_detects_trusted_store_corruption_test() {
  let adapter = storage.inmemory()
  let bytes = <<"intact">>
  let ref = Ref(hash_bytes(bytes))
  storage.insert_content(adapter, ref, bytes) |> should.equal(Ok(Nil))
  storage.check_content(adapter, ref) |> should.equal(Ok(Nil))
  adapter.insert(ref, <<"corruption">>) |> should.equal(Ok(Nil))
  storage.check_content(adapter, ref) |> should.be_error
  storage.check_content(adapter, Ref(hash_bytes(<<"missing">>)))
  |> should.equal(Error(storage.NotFound))
}

pub fn rejected_write_preserves_existing_content_test() {
  let adapter = storage.inmemory()
  let bytes = <<"valid binding">>
  let ref = Ref(hash_bytes(bytes))
  storage.insert_content(adapter, ref, bytes) |> should.equal(Ok(Nil))
  storage.insert_content(adapter, ref, <<"forged replacement">>)
  |> should.be_error
  adapter.lookup(ref) |> should.equal(Ok(Some(bytes)))
}
