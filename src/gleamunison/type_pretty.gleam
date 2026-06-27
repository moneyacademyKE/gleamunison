import glam/doc.{type Document}
import gleam/int
import gleam/list
import gleamunison/ast.{type Type}
import gleamunison/identity.{Ref, hash_to_short_string}

fn get_char(alphabet: List(String), index: Int) -> String {
  case alphabet, index {
    [char, ..], 0 -> char
    [_, ..rest], n -> get_char(rest, n - 1)
    [], _ -> ""
  }
}

fn var_name(index: Int) -> String {
  let alphabet = [
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
  ]
  case index < 26 {
    True -> get_char(alphabet, index)
    False -> {
      let char_idx = index % 26
      let suffix = index / 26
      get_char(alphabet, char_idx) <> int.to_string(suffix)
    }
  }
}

pub fn type_to_doc(t: Type) -> Document {
  case t {
    ast.TypeVar(idx) -> doc.from_string(var_name(idx))
    ast.AbilityVar(idx) -> doc.from_string("e" <> int.to_string(idx))
    ast.Builtin(ast.IntType) -> doc.from_string("Int")
    ast.Builtin(ast.FloatType) -> doc.from_string("Float")
    ast.Builtin(ast.TextType) -> doc.from_string("Text")
    ast.Builtin(ast.BoolType) -> doc.from_string("Boolean")
    ast.Builtin(ast.ListType) -> doc.from_string("List")
    ast.Builtin(ast.HandlerType) -> doc.from_string("Handler")
    ast.App(name_ref, args) -> {
      let Ref(hash) = name_ref
      let name_doc = doc.from_string("#" <> hash_to_short_string(hash))
      case args {
        [] -> name_doc
        _ -> {
          let arg_docs = list.map(args, type_to_doc)
          doc.group(
            doc.concat([
              name_doc,
              doc.from_string("["),
              doc.nest(
                doc.concat([
                  doc.soft_break,
                  doc.join(
                    arg_docs,
                    with: doc.concat([doc.from_string(","), doc.space]),
                  ),
                ]),
                2,
              ),
              doc.soft_break,
              doc.from_string("]"),
            ]),
          )
        }
      }
    }
    ast.Fn(params, result, requires) -> {
      let param_docs = list.map(params, type_to_doc)
      let result_doc = type_to_doc(result)

      let ast.Required(abilities) = requires
      let req_doc = case abilities {
        [] -> doc.from_string("")
        _ -> {
          let ability_docs =
            list.map(abilities, fn(el) {
              case el {
                ast.ReqVar(idx) -> doc.from_string("e" <> int.to_string(idx))
                ast.Concrete(ast.AbilityRef(Ref(hash))) ->
                  doc.from_string("#" <> hash_to_short_string(hash))
              }
            })
          doc.concat([
            doc.from_string("{"),
            doc.join(
              ability_docs,
              with: doc.concat([doc.from_string(","), doc.space]),
            ),
            doc.from_string("}"),
          ])
        }
      }

      let arrow = doc.concat([doc.from_string("->"), req_doc])

      let all_parts = list.append(param_docs, [result_doc])
      doc.group(doc.join(
        all_parts,
        with: doc.concat([doc.space, arrow, doc.space]),
      ))
    }
  }
}

pub fn pretty_print(t: Type) -> String {
  type_to_doc(t)
  |> doc.to_string(80)
}
