import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleamunison/identity.{type DefinitionRef, type Hash, Local, Ref, hash_bytes, hash_equal, hash_to_debug_string}
import gleamunison/ast as ast
import gleamunison/storage.{type StorageAdapter, inmemory}

fn str_to_bits(s: String) -> BitArray { bit_array.from_string(s) }

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

fn hash_to_binary(h: Hash) -> BitArray { str_to_bits(hash_to_debug_string(h)) }

fn hash_term(term: ast.Term) -> Hash {
  case term {
    ast.Int(n) -> hash_bytes(str_to_bits("int:" <> int.to_string(n)))
    ast.Float(f) -> hash_bytes(str_to_bits("float:" <> float.to_string(f)))
    ast.Text(b) -> hash_bytes(bit_array.concat([str_to_bits("text:"), b]))
    ast.List(ts) ->
      hash_bytes(bit_array.concat([str_to_bits("list:")] |> list.append(list.map(ts, fn(t) { hash_to_binary(hash_term(t)) }))))
    ast.Lambda(binder: Local(i), body:) ->
      hash_bytes(bit_array.concat([str_to_bits("lam:" <> int.to_string(i) <> ":"), hash_to_binary(hash_term(body))]))
    ast.Apply(function: f, arg: a) ->
      hash_bytes(bit_array.concat([str_to_bits("app:"), hash_to_binary(hash_term(f)), hash_to_binary(hash_term(a))]))
    ast.Let(binder: Local(i), value: v, body: b) ->
      hash_bytes(bit_array.concat([str_to_bits("let:" <> int.to_string(i) <> ":"), hash_to_binary(hash_term(v)), hash_to_binary(hash_term(b))]))
    _ -> hash_bytes(str_to_bits("term:other"))
  }
}

fn hash_type(typ: ast.Type) -> Hash {
  case typ {
    ast.Builtin(ast.IntType) -> hash_bytes(str_to_bits("int"))
    ast.Builtin(ast.FloatType) -> hash_bytes(str_to_bits("float"))
    ast.Builtin(ast.TextType) -> hash_bytes(str_to_bits("text"))
    ast.TypeVar(i) -> hash_bytes(str_to_bits("var:" <> int.to_string(i)))
    _ -> hash_bytes(str_to_bits("type"))
  }
}

pub fn hash_of_definition(def: ast.Definition) -> Hash {
  case def {
    ast.TermDef(term:, typ:) ->
      hash_bytes(bit_array.concat([hash_to_binary(hash_term(term)), hash_to_binary(hash_type(typ))]))
    ast.TypeDef(td) -> hash_bytes(str_to_bits(string.inspect(td)))
    ast.AbilityDecl(ad) -> hash_bytes(str_to_bits(string.inspect(ad)))
  }
}

fn verify_and_store(codebase: Codebase, ref: DefinitionRef, def: ast.Definition) -> Result(Codebase, InsertError) {
  let computed = hash_of_definition(def)
  let Ref(hash) = ref
  case hash_equal(computed, hash) {
    False -> Error(HashMismatch(hash_expected: computed, hash_got: hash))
    True -> {
      case dict.get(codebase.seen, computed) {
        Ok(existing) -> Error(DuplicateDef(existing, ref))
        Error(_) -> Ok(Codebase(..codebase, seen: dict.insert(codebase.seen, computed, ref)))
      }
    }
  }
}

pub fn insert(codebase: Codebase, unit: ast.Unit) -> Result(Codebase, InsertError) {
  let ast.Unit(root: _, defs:) = unit
  list.fold(defs, Ok(codebase), fn(acc, kv) {
    case acc {
      Ok(cb) -> verify_and_store(cb, kv.0, kv.1)
      Error(_) -> acc
    }
  })
}
