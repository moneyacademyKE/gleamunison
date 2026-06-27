import gleam/dict
import gleamunison/ast
import gleamunison/elab_types.{
  type ElaborateError, type Typ, TBuiltin, TCon, TFun, TVar, UnsupportedTypeRef,
}
import gleamunison/identity.{Local}

pub fn lower_type_ref(
  t: Typ,
  vars: dict.Dict(String, Int),
) -> Result(#(ast.TypeRef, dict.Dict(String, Int)), ElaborateError) {
  case t {
    TVar(name) -> {
      case dict.get(vars, name) {
        Ok(i) -> Ok(#(ast.TypeRefVar(Local(i)), vars))
        Error(_) -> {
          let i = dict.size(vars)
          Ok(#(ast.TypeRefVar(Local(i)), dict.insert(vars, name, i)))
        }
      }
    }
    TCon(r) -> Ok(#(ast.TypeCon(r), vars))
    TBuiltin(b) -> {
      let bt = case b {
        elab_types.TInt -> ast.IntType
        elab_types.TFloat -> ast.FloatType
        elab_types.TText -> ast.TextType
        elab_types.TList -> ast.ListType
      }
      Ok(#(ast.TypeRefBuiltin(bt), vars))
    }
    TFun(_, _) -> Error(UnsupportedTypeRef("TFun not supported"))
  }
}

pub fn type_ref_to_type(tr: ast.TypeRef) -> ast.Type {
  case tr {
    ast.TypeRefVar(Local(i)) -> ast.TypeVar(i)
    ast.TypeCon(r) -> ast.App(r, [])
    ast.TypeRefBuiltin(bt) -> ast.Builtin(bt)
  }
}
