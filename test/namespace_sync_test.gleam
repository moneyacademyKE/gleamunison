import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{Ref}
import gleamunison/namespace
import gleamunison/storage
import gleeunit/should

fn seed_adapter() -> storage.StorageAdapter {
  let adapter = storage.inmemory()
  let def = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let ref = Ref(codebase.hash_of_definition(def))
  let unit = ast.Unit(ref, [#(ref, def)])
  let assert Ok(_) = codebase.insert(codebase.with_adapter(adapter), unit)
  adapter
}

/// Push a branch on one store, export it, import into another: the branch
/// head and every name in its namespace must resolve identically on the
/// far side. Names travel with the code — that is the whole point.
pub fn branch_round_trip_between_adapters_test() {
  let src = seed_adapter()
  let dst = seed_adapter()

  let ns0 = namespace.empty()
  let def = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let def_ref = Ref(codebase.hash_of_definition(def))
  let ns1 = namespace.set(ns0, "answer", def_ref)
  let assert Ok(head_ref) = namespace.commit(src, "main", ns1)

  // Far side has never heard of the branch.
  namespace.branch_head(dst, "main") |> should.be_error

  let assert Ok(chunks) = namespace.export_branch(src, "main")
  let assert Ok(_) = namespace.import_branch(dst, chunks)

  let assert Ok(#(seq, ns_ref)) = namespace.branch_head(dst, "main")
  seq |> should.equal(1)
  let assert Ok(loaded) = namespace.load(dst, ns_ref)
  namespace.get(loaded, "answer") |> should.equal(Ok(def_ref))
  // Causal identity survives: the head ref is the same content hash.
  let assert Ok(#(_, src_ns_ref)) = namespace.branch_head(src, "main")
  src_ns_ref |> should.equal(ns_ref)
  let _ = head_ref
  Nil
}

/// Importing verifies chunk integrity: a tampered byte must be refused.
pub fn import_refuses_tampered_chunk_test() {
  let src = seed_adapter()
  let dst = seed_adapter()
  let ns0 = namespace.empty()
  let assert Ok(_) = namespace.commit(src, "main", ns0)
  let assert Ok(chunks) = namespace.export_branch(src, "main")
  let tampered = list_map_first(chunks, fn(pair) { #(pair.0, <<"tampered">>) })
  namespace.import_branch(dst, tampered) |> should.be_error
}

fn list_map_first(
  xs: List(#(String, BitArray)),
  f: fn(#(String, BitArray)) -> #(String, BitArray),
) -> List(#(String, BitArray)) {
  case xs {
    [] -> []
    [first, ..rest] -> [f(first), ..rest]
  }
}

/// The branch pointer ref is derivable from the branch name alone — that
/// is what lets a remote peer request it without a negotiation round.
pub fn branch_pointer_ref_is_derivable_test() {
  let a = namespace.branch_pointer_ref("main")
  let b = namespace.branch_pointer_ref("main")
  a |> should.equal(b)
  let c = namespace.branch_pointer_ref("other")
  should_not_equal(a, b, c)
}

fn should_not_equal(a: r, _b: r, c: r) -> Nil {
  case a == c {
    True -> panic as "distinct branches must derive distinct refs"
    False -> Nil
  }
}
