import gleamunison/identity.{type DefinitionRef, type LocalVar}

pub type Type {
  TypeVar(index: Int)
  AbilityVar(index: Int)
  Fn(params: List(Type), result: Type, requires: Requirement)
  App(name: DefinitionRef, args: List(Type))
  Builtin(BuiltinType)
}

pub type BuiltinType {
  IntType
  FloatType
  TextType
  BoolType
  ListType
  HandlerType
}

pub type AbilityRef {
  AbilityRef(decl: DefinitionRef)
}

pub type ReqElement {
  Concrete(AbilityRef)
  ReqVar(index: Int)
}

pub type Requirement {
  Required(abilities: List(ReqElement))
}

pub type Term {
  RefTo(DefinitionRef)
  LocalVarRef(LocalVar)
  Int(Int)
  Float(Float)
  Text(BitArray)
  List(List(Term))
  Apply(function: Term, arg: Term)
  Lambda(binder: LocalVar, body: Term)
  Let(binder: LocalVar, value: Term, body: Term)
  Match(scrutinee: Term, cases: List(Case))
  Do(ability: DefinitionRef, operation: LocalVar, args: List(Term))
  Handle(computation: Term, handler: Term)
}

pub type Case {
  Case(pattern: Pattern, body: Term)
}

pub type Pattern {
  PatVar(LocalVar)
  PatInt(Int)
  PatText(BitArray)
  PatCons(head: LocalVar, tail: LocalVar)
  PatEmptyList
  PatAs(bound: LocalVar, inner: Pattern)
}

pub type TypeDeclaration {
  Structural(name: LocalVar, parameters: List(LocalVar), constructors: List(Constructor))
  Unique(name: LocalVar, guid: String, parameters: List(LocalVar), constructors: List(Constructor))
}

pub type Constructor {
  Constructor(name: LocalVar, args: List(TypeRef))
}

pub type TypeRef {
  TypeRefVar(LocalVar)
  TypeCon(DefinitionRef)
}

pub type AbilityDeclaration {
  AbilityDeclaration(name: LocalVar, operations: List(Operation))
}

pub type Operation {
  Operation(name: LocalVar, inputs: List(TypeRef), output: TypeRef)
}

pub type Definition {
  TermDef(term: Term, typ: Type)
  TypeDef(TypeDeclaration)
  AbilityDecl(AbilityDeclaration)
}

pub type Unit {
  Unit(root: DefinitionRef, defs: List(#(DefinitionRef, Definition)))
}
