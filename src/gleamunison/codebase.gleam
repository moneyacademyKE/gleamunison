import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

import gleamunison/ast
import gleamunison/identity.{
  type DefinitionRef, type Hash, Local, Ref, hash_bytes, hash_equal,
  hash_to_debug_string,
}
import gleamunison/storage.{type StorageAdapter, inmemory}

fn str_to_bits(s: String) -> BitArray {
  bit_array.from_string(s)
}

pub opaque type Codebase {
  Codebase(adapter: StorageAdapter, seen: Dict(Hash, DefinitionRef))
}

pub fn empty() -> Codebase {
  Codebase(adapter: inmemory(), seen: dict.new())
}

pub type InsertError {
  HashMismatch(hash_expected: Hash, hash_got: Hash)
  DuplicateDef(existing: DefinitionRef, incoming: DefinitionRef)
}

fn hash_to_binary(h: Hash) -> BitArray {
  str_to_bits(hash_to_debug_string(h))
}

fn hash_type_ref(tr: ast.TypeRef) -> Hash {
  case tr {
    ast.TypeRefVar(Local(i)) ->
      hash_bytes(str_to_bits("typerefvar:" <> int.to_string(i)))
    ast.TypeCon(Ref(h)) ->
      hash_bytes(bit_array.concat([str_to_bits("typecon:"), hash_to_binary(h)]))
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
      ..list.map(args, fn(a) { hash_to_binary(hash_type_ref(a)) })
    ]),
  )
}

fn hash_operation(op: ast.Operation) -> Hash {
  let ast.Operation(Local(i), inputs, output) = op
  hash_bytes(
    bit_array.concat([
      str_to_bits("operation:" <> int.to_string(i)),
      hash_to_binary(hash_type_ref(output)),
      ..list.map(inputs, fn(inp) { hash_to_binary(hash_type_ref(inp)) })
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
          hash_to_binary(hash_pattern(inner)),
        ]),
      )
    ast.PatConstructor(ctor_ref: Ref(h), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("patctor:"),
          hash_to_binary(h),
          ..list.map(args, fn(a) { hash_to_binary(hash_pattern(a)) })
        ]),
      )
  }
}

fn hash_case(c: ast.Case) -> Hash {
  hash_bytes(
    bit_array.concat([
      str_to_bits("case:"),
      hash_to_binary(hash_pattern(c.pattern)),
      hash_to_binary(hash_term(c.body)),
    ]),
  )
}

fn hash_term(term: ast.Term) -> Hash {
  case term {
    ast.Int(n) -> hash_bytes(str_to_bits("int:" <> int.to_string(n)))
    ast.Float(f) -> hash_bytes(str_to_bits("float:" <> float.to_string(f)))
    ast.Text(b) -> hash_bytes(bit_array.concat([str_to_bits("text:"), b]))
    ast.List(ts) ->
      hash_bytes(bit_array.concat(
        [str_to_bits("list:")]
        |> list.append(list.map(ts, fn(t) { hash_to_binary(hash_term(t)) })),
      ))
    ast.Lambda(binder: Local(i), body:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("lam:" <> int.to_string(i) <> ":"),
          hash_to_binary(hash_term(body)),
        ]),
      )
    ast.Apply(function: f, arg: a) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("app:"),
          hash_to_binary(hash_term(f)),
          hash_to_binary(hash_term(a)),
        ]),
      )
    ast.Let(binder: Local(i), value: v, body: b) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("let:" <> int.to_string(i) <> ":"),
          hash_to_binary(hash_term(v)),
          hash_to_binary(hash_term(b)),
        ]),
      )
    ast.LocalVarRef(Local(i)) ->
      hash_bytes(str_to_bits("localvar:" <> int.to_string(i)))
    ast.RefTo(Ref(h)) ->
      hash_bytes(bit_array.concat([str_to_bits("refto:"), hash_to_binary(h)]))
    ast.Match(scrutinee:, cases:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("match:"),
          hash_to_binary(hash_term(scrutinee)),
          ..list.map(cases, fn(c) { hash_to_binary(hash_case(c)) })
        ]),
      )
    ast.Do(ability: Ref(h), operation: Local(op_i), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("do:" <> int.to_string(op_i) <> ":"),
          hash_to_binary(h),
          ..list.map(args, fn(a) { hash_to_binary(hash_term(a)) })
        ]),
      )
    ast.Handle(computation:, handler:, ability: Ref(h)) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("handle:"),
          hash_to_binary(h),
          hash_to_binary(hash_term(computation)),
          hash_to_binary(hash_term(handler)),
        ]),
      )
    ast.Construct(ctor_ref: Ref(h), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("construct:"),
          hash_to_binary(h),
          ..list.map(args, fn(a) { hash_to_binary(hash_term(a)) })
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
    ast.Fn(params:, result:, requires: _) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("fn:"),
          hash_to_binary(hash_type(result)),
          ..list.map(params, fn(p) { hash_to_binary(hash_type(p)) })
        ]),
      )
    ast.App(Ref(h), args:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("app:"),
          hash_to_binary(h),
          ..list.map(args, fn(a) { hash_to_binary(hash_type(a)) })
        ]),
      )
  }
}

pub fn hash_of_definition(def: ast.Definition) -> Hash {
  case def {
    ast.TermDef(term:, typ:) ->
      hash_bytes(
        bit_array.concat([
          str_to_bits("termdef:"),
          hash_to_binary(hash_term(term)),
          hash_to_binary(hash_type(typ)),
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
          hash_to_binary(h1),
          ..list.map(constructors, fn(c) { hash_to_binary(hash_constructor(c)) })
        ]),
      )
    }
    ast.TypeDef(ast.Unique(Local(n), guid:, parameters: _, constructors: _)) ->
      hash_bytes(str_to_bits(
        "typedef:unique:" <> int.to_string(n) <> ":" <> guid,
      ))
    ast.AbilityDecl(ast.AbilityDeclaration(Local(n), operations:)) -> {
      hash_bytes(
        bit_array.concat([
          str_to_bits("abilitydecl:" <> int.to_string(n)),
          ..list.map(operations, fn(op) { hash_to_binary(hash_operation(op)) })
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
    True ->
      case dict.get(codebase.seen, computed) {
        Ok(_existing) -> Ok(codebase)
        // idempotent: same content-addressed content
        Error(_) -> {
          let _ =
            codebase.adapter.insert(
              ref,
              bit_array.from_string(string.inspect(def)),
            )
          Ok(
            Codebase(
              ..codebase,
              seen: dict.insert(codebase.seen, computed, ref),
            ),
          )
        }
      }
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

pub fn insert_raw(
  codebase: Codebase,
  ref: DefinitionRef,
  bytes: BitArray,
) -> Codebase {
  let _ = codebase.adapter.insert(ref, bytes)
  let Ref(h) = ref
  Codebase(..codebase, seen: dict.insert(codebase.seen, h, ref))
}

pub fn get_adapter(codebase: Codebase) -> StorageAdapter {
  codebase.adapter
}
