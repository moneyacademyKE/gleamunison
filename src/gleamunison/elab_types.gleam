import gleamunison/identity.{type DefinitionRef}

pub type SurfaceTerm {
  SInt(Int)
  SFloat(Float)
  SText(BitArray)
  SList(List(SurfaceTerm))
  SVar(String)
  SRef(DefinitionRef)
  SApply(function: SurfaceTerm, arg: SurfaceTerm)
  SLambda(param: String, body: SurfaceTerm)
  SLet(name: String, value: SurfaceTerm, body: SurfaceTerm)
  SMatch(scrutinee: SurfaceTerm, cases: List(SCase))
  SDo(ability: String, operation: String, args: List(SurfaceTerm))
  SHandle(computation: SurfaceTerm, handler: SurfaceTerm, ability: String)
}

pub type SCase {
  SCase(pattern: SPattern, body: SurfaceTerm)
}

pub type SPattern {
  SPVar(String)
  SPInt(Int)
  SPText(BitArray)
  SPCons(head: String, tail: String)
  SPEmptyList
  SPAs(name: String, inner: SPattern)
}

pub type SurfaceUnit {
  SurfaceUnit(root: DefinitionRef, defs: List(#(String, SurfaceDef)))
}

pub type SurfaceDef {
  SurfaceTermDef(SurfaceTerm)
  SurfaceTypeDef(Typ)
  SurfaceAbilityDef(name: String, ops: List(SurfaceOp))
}

pub type Typ {
  TVar(String)
  TCon(DefinitionRef)
  TFun(params: List(Typ), result: Typ)
  TBuiltin(BuiltinName)
}

pub type BuiltinName {
  TInt
  TFloat
  TText
  TList
}

pub type SurfaceOp {
  SurfaceOp(name: String, inputs: List(Typ), output: Typ)
}

pub type ElaborateError {
  NameNotFound(String)
  UnknownOperation(ability: String, op: String)
  MissingAbilityDecl(String)
  InferFailed(message: String)
  UnsupportedTypeRef(description: String)
}
