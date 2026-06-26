import gleamunison/identity.{Local}
import gleamunison/ast
import gleamunison/elab_types.{type Typ, type ElaborateError, TVar, TCon, TBuiltin, TFun, UnsupportedTypeRef}

pub fn lower_type_ref(t: Typ) -> Result(ast.TypeRef, ElaborateError) {
  case t {
    TVar(_) -> Ok(ast.TypeRefVar(Local(0)))
    TCon(r) -> Ok(ast.TypeCon(r))
    TBuiltin(b) -> {
      let bt = case b {
        elab_types.TInt -> ast.IntType
        elab_types.TFloat -> ast.FloatType
        elab_types.TText -> ast.TextType
        elab_types.TList -> ast.ListType
      }
      Ok(ast.TypeRefBuiltin(bt))
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
