import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

import gleam/option
import gleamunison/ast
import gleamunison/definition_codec
import gleamunison/identity.{
  type DefinitionRef, type Hash, Local, Ref, hash_bytes, hash_equal,
  hash_to_debug_string, hash_to_hash_input,
}
import gleamunison/storage.{type StorageAdapter, inmemory}

fn str_to_bits(s: String) -> BitArray {
  bit_array.from_string(s)
}

pub opaque type Codebase {
  Codebase(adapter: StorageAdapter)
}

pub fn empty() -> Codebase {
  Codebase(adapter: inmemory())
}

/// A codebase over a caller-chosen adapter (dets for persistence, mnesia
/// for replication). Sync and CLI paths need real storage, not inmemory.
pub fn with_adapter(adapter: StorageAdapter) -> Codebase {
  Codebase(adapter: adapter)
}

pub type InsertError {
  HashMismatch(hash_expected: Hash, hash_got: Hash)
  DuplicateDef(existing: DefinitionRef, incoming: DefinitionRef)
  StorageFailure(storage.StorageError)
}

/// The one place an InsertError becomes a user sentence. Rendering belongs
/// here, with the type, rather than at each call site — inspect output is
/// a debug rendering and must never reach a user.
pub fn describe_insert_error(error: InsertError) -> String {
  case error {
    HashMismatch(expected, got) ->
      "hash mismatch: expected "
      <> identity.ref_hex(Ref(expected))
      <> ", got "
      <> identity.ref_hex(Ref(got))
    DuplicateDef(existing, incoming) ->
      "duplicate definition: "
      <> identity.ref_hex(incoming)
      <> " already stored as "
      <> identity.ref_hex(existing)
    StorageFailure(error) -> storage.describe_error(error)
  }
}

/// The one place a ReadError becomes a user sentence. Same rule as
/// describe_insert_error: rendering belongs with the type, and inspect
/// output must never reach a user. NotFound carries no sentence here —
/// callers with a "missing" vocabulary of their own name it there.
pub fn describe_read_error(error: ReadError) -> String {
  case error {
    NotFound(_) -> "not in the store"
    StoreFailure(error) -> storage.describe_error(error)
    Corrupt(_, reason) -> "content does not match its ref: " <> reason
    DecodeFailed(_, reason) -> "payload is not a definition: " <> reason
  }
}

fn hash_type_ref(tr: ast.TypeRef) -> Hash {
  case tr {
    ast.TypeRefVar(Local(i)) ->
      hash_bytes(str_to_bits("typerefvar:" <> int.to_string(i)))
    ast.TypeCon(Ref(h)) ->
      hash_bytes(
        bit_array.concat([str_to_bits("typecon:"), hash_to_hash_input(h)]),
      )
    ast.TypeRefBuiltin(bt) -> {
      let name = case bt {
        ast.IntType -> "int"
        ast.FloatType -> "float"
        ast.TextType -> "text"
        ast.BoolType -> "bool"
        ast.ListType -> "list"
        ast.HandlerType -> "handler"
      }
      hash_bytes(str_to_bits("typebuiltin:" <> name))
    }
  }
}

fn hash_constructor(c: ast.Constructor) -> Hash {
  let ast.Constructor(Local(i), args) = c
  hash_bytes(
    bit_array.concat([
      str_to_bits("constructor:" <> int.to_string(i)),
      ..list.map(args, fn(a) { hash_to_hash_input(hash_type_ref(a)) })
    ]),
  )
}

fn hash_operation(op: ast.Operation) -> Hash {
  let ast.Operation(Local(i), inputs, output) = op
  hash_bytes(
    bit_array.concat([
      str_to_bits("operation:" <> int.to_string(i)),
      hash_to_hash_input(hash_type_ref(output)),
      ..list.map(inputs, fn(inp) { hash_to_hash_input(hash_type_ref(inp)) })
    ]),
  )
}

fn hash_pattern(p: ast.Pattern) -> Hash {
  case p {
    ast.PatVar(Local(i)) ->
      hash_bytes(str_to_bits("patvar:" <> int.to_string(i)))
    ast.PatInt(n) -> hash_bytes(str_to_bits("patint:" <> int.to_string(n)))
    ast.PatText(b) -> hash_bytes(bit_array.concat([str_to_bits("pattext:"), b]))
    ast.PatCons(head: Local(h), tail: Local(t)) ->
      hash_bytes(str_to_bits(
        "patcons:" <> int.to_string(h) <> ":" <> int.to_string(t),
      ))
    ast.PatEmptyList -> hash_bytes(str_to_bits("patempty"))
    ast.PatAs(bound: Local(i), inner:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("patas:" <> int.to_string(i) <> ":"),
          hash_to_hash_input(hash_pattern(inner)),
        ]),
      )
    ast.PatConstructor(ctor_ref: Ref(h), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("patctor:"),
          hash_to_hash_input(h),
          ..list.map(args, fn(a) { hash_to_hash_input(hash_pattern(a)) })
        ]),
      )
  }
}

fn hash_case(c: ast.Case) -> Hash {
  let guard_hash = case c.guard {
    option.Some(ast.GuardTerm(t)) -> hash_term(t)
    option.None -> hash_bytes(str_to_bits("noguard"))
  }
  hash_bytes(
    bit_array.concat([
      str_to_bits("case:"),
      hash_to_hash_input(hash_pattern(c.pattern)),
      hash_to_hash_input(guard_hash),
      hash_to_hash_input(hash_term(c.body)),
    ]),
  )
}

fn hash_term(term: ast.Term) -> Hash {
  case term {
    // Metadata wrapper: identity is structural, so the span is skipped.
    ast.Located(inner, _) -> hash_term(inner)
    ast.Int(n) -> hash_bytes(str_to_bits("int:" <> int.to_string(n)))
    ast.Float(f) -> hash_bytes(str_to_bits("float:" <> float.to_string(f)))
    ast.Text(b) -> hash_bytes(bit_array.concat([str_to_bits("text:"), b]))
    ast.List(ts) ->
      hash_bytes(bit_array.concat(
        [str_to_bits("list:")]
        |> list.append(list.map(ts, fn(t) { hash_to_hash_input(hash_term(t)) })),
      ))
    ast.Lambda(binder: Local(i), body:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("lam:" <> int.to_string(i) <> ":"),
          hash_to_hash_input(hash_term(body)),
        ]),
      )
    ast.Apply(function: f, arg: a) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("app:"),
          hash_to_hash_input(hash_term(f)),
          hash_to_hash_input(hash_term(a)),
        ]),
      )
    ast.Let(binder: Local(i), value: v, body: b) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("let:" <> int.to_string(i) <> ":"),
          hash_to_hash_input(hash_term(v)),
          hash_to_hash_input(hash_term(b)),
        ]),
      )
    ast.LocalVarRef(Local(i)) ->
      hash_bytes(str_to_bits("localvar:" <> int.to_string(i)))
    ast.RefTo(Ref(h)) ->
      hash_bytes(
        bit_array.concat([str_to_bits("refto:"), hash_to_hash_input(h)]),
      )
    ast.Match(scrutinee:, cases:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("match:"),
          hash_to_hash_input(hash_term(scrutinee)),
          ..list.map(cases, fn(c) { hash_to_hash_input(hash_case(c)) })
        ]),
      )
    ast.Do(ability: Ref(h), operation: Local(op_i), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("do:" <> int.to_string(op_i) <> ":"),
          hash_to_hash_input(h),
          ..list.map(args, fn(a) { hash_to_hash_input(hash_term(a)) })
        ]),
      )
    ast.Handle(computation:, handler:, ability: Ref(h)) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("handle:"),
          hash_to_hash_input(h),
          hash_to_hash_input(hash_term(computation)),
          hash_to_hash_input(hash_term(handler)),
        ]),
      )
    ast.Construct(ctor_ref: Ref(h), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("construct:"),
          hash_to_hash_input(h),
          ..list.map(args, fn(a) { hash_to_hash_input(hash_term(a)) })
        ]),
      )
    ast.Hole -> hash_bytes(str_to_bits("hole"))
    ast.Use(binder: Local(i), call:, body:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("use:" <> int.to_string(i) <> ":"),
          hash_to_hash_input(hash_term(call)),
          hash_to_hash_input(hash_term(body)),
        ]),
      )
  }
}

fn hash_type(typ: ast.Type) -> Hash {
  case typ {
    ast.Builtin(ast.IntType) -> hash_bytes(str_to_bits("int"))
    ast.Builtin(ast.FloatType) -> hash_bytes(str_to_bits("float"))
    ast.Builtin(ast.TextType) -> hash_bytes(str_to_bits("text"))
    ast.Builtin(ast.BoolType) -> hash_bytes(str_to_bits("bool"))
    ast.Builtin(ast.ListType) -> hash_bytes(str_to_bits("list"))
    ast.Builtin(ast.HandlerType) -> hash_bytes(str_to_bits("handler"))
    ast.TypeVar(i) -> hash_bytes(str_to_bits("var:" <> int.to_string(i)))
    ast.AbilityVar(i) ->
      hash_bytes(str_to_bits("abilityvar:" <> int.to_string(i)))
    ast.Fn(params:, result:, requires:) ->
      hash_bytes(
        bit_array.concat(list.append(
          [
            str_to_bits("fn:"),
            hash_to_hash_input(hash_type(result)),
            ..list.map(params, fn(p) { hash_to_hash_input(hash_type(p)) })
          ],
          requirement_bytes(requires),
        )),
      )
    ast.App(Ref(h), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("app:"),
          hash_to_hash_input(h),
          ..list.map(args, fn(a) { hash_to_hash_input(hash_type(a)) })
        ]),
      )
  }
}

fn requirement_bytes(requirement: ast.Requirement) -> List(BitArray) {
  let ast.Required(abilities) = requirement
  case abilities {
    [] -> []
    _ -> {
      let parts =
        list.map(abilities, fn(ability) {
          case ability {
            ast.ReqVar(i) -> "var:" <> int.to_string(i)
            ast.Concrete(ast.AbilityRef(Ref(h))) ->
              "ref:" <> hash_to_debug_string(h)
          }
        })
        |> list.unique
        |> list.sort(string.compare)
      [
        str_to_bits("requires:"),
        ..list.map(parts, fn(part) {
          hash_to_hash_input(hash_bytes(str_to_bits(part)))
        })
      ]
    }
  }
}

pub fn hash_of_definition(def: ast.Definition) -> Hash {
  case def {
    ast.TermDef(term:, typ:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("termdef:"),
          hash_to_hash_input(hash_term(term)),
          hash_to_hash_input(hash_type(typ)),
        ]),
      )
    ast.TypeDef(ast.Structural(Local(n), parameters:, constructors:)) -> {
      let h1 =
        hash_bytes(
          bit_array.concat([
            str_to_bits("typedef:structural:" <> int.to_string(n)),
            ..list.map(parameters, fn(param) {
              let Local(i) = param
              str_to_bits("p" <> int.to_string(i))
            })
          ]),
        )
      hash_bytes(
        bit_array.concat([
          hash_to_hash_input(h1),
          ..list.map(constructors, fn(c) {
            hash_to_hash_input(hash_constructor(c))
          })
        ]),
      )
    }
    ast.TypeDef(ast.Unique(Local(n), guid:, parameters:, constructors:)) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("typedef:unique:" <> int.to_string(n) <> ":" <> guid),
          str_to_bits(":schema:"),
          hash_to_hash_input(
            hash_of_definition(
              ast.TypeDef(ast.Structural(Local(n), parameters, constructors)),
            ),
          ),
        ]),
      )
    ast.AbilityDecl(ast.AbilityDeclaration(Local(n), operations:)) -> {
      hash_bytes(
        bit_array.concat([
          str_to_bits("abilitydecl:" <> int.to_string(n)),
          ..list.map(operations, fn(op) {
            hash_to_hash_input(hash_operation(op))
          })
        ]),
      )
    }
  }
}

fn verify_and_store(
  codebase: Codebase,
  ref: DefinitionRef,
  def: ast.Definition,
) -> Result(Codebase, InsertError) {
  let computed = hash_of_definition(def)
  let Ref(hash) = ref
  case hash_equal(computed, hash) {
    False -> Error(HashMismatch(hash_expected: computed, hash_got: hash))
    True -> insert_raw_checked(codebase, ref, definition_codec.encode(def))
  }
}

pub fn insert(
  codebase: Codebase,
  unit: ast.Unit,
) -> Result(Codebase, InsertError) {
  list.fold(unit.defs, Ok(codebase), fn(acc, kv) {
    case acc {
      Ok(cb) -> verify_and_store(cb, kv.0, kv.1)
      Error(_) -> acc
    }
  })
}

pub fn insert_raw_checked(
  codebase: Codebase,
  ref: DefinitionRef,
  bytes: BitArray,
) -> Result(Codebase, InsertError) {
  use Nil <- result.try(
    storage.insert_content(codebase.adapter, ref, bytes)
    |> result.map_error(StorageFailure),
  )
  Ok(codebase)
}

pub type ReadError {
  NotFound(DefinitionRef)
  StoreFailure(storage.StorageError)
  Corrupt(ref: DefinitionRef, reason: String)
  DecodeFailed(ref: DefinitionRef, reason: String)
}

/// The read half of the store. Identity is the ref, so a stored payload is
/// re-verified before it is decoded: a store that disagrees with its own keys
/// must not be able to hand a different definition to the loader.
pub fn get(
  codebase: Codebase,
  ref: DefinitionRef,
) -> Result(ast.Definition, ReadError) {
  case codebase.adapter.lookup(ref) {
    Ok(option.None) -> Error(NotFound(ref))
    Ok(option.Some(bytes)) ->
      case storage.verify_content(ref, bytes) {
        Error(error) -> Error(Corrupt(ref, storage.describe_error(error)))
        Ok(Nil) ->
          case definition_codec.decode(bytes) {
            Ok(definition) -> Ok(definition)
            Error(reason) -> Error(DecodeFailed(ref, reason))
          }
      }
    Error(error) -> Error(StoreFailure(error))
  }
}

pub fn get_adapter(codebase: Codebase) -> StorageAdapter {
  codebase.adapter
}
