import gleam/option.{type Option}
import gleamunison/identity.{type DefinitionRef}

/// Source location (1-based line and column) carried from the lexer
/// through elaboration so errors can name the place they happened.
pub type Span {
  Span(line: Int, col: Int)
}

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
  SConstruct(name: String, args: List(SurfaceTerm))
  SLabeledFn(params: List(#(String, SurfaceTerm)), body: SurfaceTerm)
  SHole
  SGuardGuard(guard: SurfaceTerm)
  SUse(binder: String, call: SurfaceTerm, body: SurfaceTerm)
  /// A term annotated with its source span. Elaboration unwraps it and
  /// attaches the span to any error raised inside.
  SLoc(inner: SurfaceTerm, span: Span)
}

pub type SCase {
  SCase(pattern: SPattern, guard: Option(SurfaceTerm), body: SurfaceTerm)
}

pub type SPattern {
  SPVar(String)
  SPInt(Int)
  SPText(BitArray)
  SPCons(head: String, tail: String)
  SPEmptyList
  SPAs(name: String, inner: SPattern)
  SPConstructor(name: String, args: List(SPattern))
}

pub type SurfaceUnit {
  SurfaceUnit(root: DefinitionRef, defs: List(#(String, SurfaceDef)))
}

pub type SurfaceDef {
  SurfaceTermDef(SurfaceTerm)
  SurfaceTypeDef(Typ)
  SurfaceAbilityDef(name: String, ops: List(SurfaceOp))
  SurfaceTypeAlias(name: String, target: Typ)
  SurfacePubTypeAlias(name: String, target: Typ)
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
  /// An error with the source span where it originated.
  At(error: ElaborateError, span: Span)
}
