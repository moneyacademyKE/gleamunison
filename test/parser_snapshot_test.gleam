import birdie
import gleam/string
import gleamunison/ast
import gleamunison/identity
import gleamunison/parser
import gleamunison/type_pretty

pub fn parser_ast_snapshot_test() {
  let assert Ok(term) =
    parser.parse_string("(let x 1 (let y 2 (lam z (list x y z))))")
  string.inspect(term)
  |> birdie.snap(title: "parser_ast_snapshot")
}

pub fn type_pretty_snapshot_test() {
  // a -> b -> List[a]
  let typ =
    ast.Fn(
      params: [ast.TypeVar(0), ast.TypeVar(1)],
      result: ast.App(
        name: identity.Ref(identity.hash_bytes(<<"list_hash">>)),
        args: [ast.TypeVar(0)],
      ),
      requires: ast.Required([]),
    )
  type_pretty.pretty_print(typ)
  |> birdie.snap(title: "type_pretty_snapshot")
}
