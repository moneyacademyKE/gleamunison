//// Runtime builtin signatures. Pure data: the type cache and effect evidence
//// both read this table, so neither keeps a partial second list of builtins.

import gleam/list
import gleamunison/ast
import gleamunison/bootstrap_types as bt
import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef}

pub type Entry =
  #(String, DefinitionRef, ast.Type)

fn v(index: Int) -> ast.Type {
  ast.TypeVar(index)
}

fn f(inputs: List(ast.Type), output: ast.Type) -> ast.Type {
  case inputs {
    [] -> output
    _ -> ast.Fn(inputs, output, ast.Required([]))
  }
}

fn host(inputs: List(ast.Type), output: ast.Type, ability: String) -> ast.Type {
  case inputs {
    [] -> output
    _ ->
      ast.Fn(
        inputs,
        output,
        ast.Required([ast.Concrete(ast.AbilityRef(bt.named(ability)))]),
      )
  }
}

fn int() -> ast.Type {
  ast.Builtin(ast.IntType)
}

fn text() -> ast.Type {
  ast.Builtin(ast.TextType)
}

fn iii() -> ast.Type {
  f([int(), int()], int())
}

fn tt() -> ast.Type {
  f([text()], text())
}

pub fn entries() -> List(Entry) {
  [
    #("add", genesis.builtin_int_add(), iii()),
    #("+", genesis.builtin_int_add(), iii()),
    #("sub", genesis.builtin_sub(), iii()),
    #("mul", genesis.builtin_mul(), iii()),
    #("div", genesis.builtin_div(), iii()),
    #("mod", genesis.builtin_mod(), iii()),
    #("read_line", genesis.builtin_io_read_line(), host([], text(), "Host")),
    #(
      "spawn",
      genesis.builtin_process_spawn(),
      host([bt.host_value()], bt.process(), "Host"),
    ),
    #("self", genesis.builtin_process_self(), host([], bt.process(), "Host")),
    #(
      "send",
      genesis.builtin_process_send(),
      host([bt.process(), bt.host_value()], bt.host_value(), "Host"),
    ),
    #("recv", genesis.builtin_process_recv(), host([], bt.host_value(), "Host")),
    #(
      "sleep",
      genesis.builtin_timer_sleep(),
      host([int()], bt.host_value(), "Host"),
    ),
    #("now", genesis.builtin_timer_now(), host([], int(), "Host")),
    #("eq?", genesis.builtin_eq(), f([v(0), v(0)], int())),
    #("lt?", genesis.builtin_lt(), f([v(0), v(0)], int())),
    #("gt?", genesis.builtin_gt(), f([v(0), v(0)], int())),
    #("and", genesis.builtin_and(), iii()),
    #("or", genesis.builtin_or(), iii()),
    #("not", genesis.builtin_not(), f([int()], int())),
    #(
      "string-concat",
      genesis.builtin_string_concat(),
      f([text(), text()], text()),
    ),
    #("string-length", genesis.builtin_string_length(), f([text()], int())),
    #(
      "string-contains?",
      genesis.builtin_string_contains(),
      f([text(), text()], int()),
    ),
    #(
      "string-slice",
      genesis.builtin_string_slice(),
      f([text(), int(), int()], text()),
    ),
    #("string-upcase", genesis.builtin_string_upcase(), tt()),
    #("string-downcase", genesis.builtin_string_downcase(), tt()),
    #(
      "string-replace",
      genesis.builtin_string_replace(),
      f([text(), text(), text()], text()),
    ),
    #(
      "string-split",
      genesis.builtin_string_split(),
      f([text(), text()], bt.list_of(text())),
    ),
    #("string-trim", genesis.builtin_string_trim(), tt()),
    #(
      "string->int",
      genesis.builtin_string_to_int(),
      f([text()], bt.either_of(int(), bt.host_value())),
    ),
    #(
      "list-length",
      genesis.builtin_list_length(),
      f([bt.list_of(v(0))], int()),
    ),
    #(
      "list-reverse",
      genesis.builtin_list_reverse(),
      f([bt.list_of(v(0))], bt.list_of(v(0))),
    ),
    #(
      "list-map",
      genesis.builtin_list_map(),
      f([f([v(0)], v(1)), bt.list_of(v(0))], bt.list_of(v(1))),
    ),
    #(
      "list-filter",
      genesis.builtin_list_filter(),
      f([f([v(0)], int()), bt.list_of(v(0))], bt.list_of(v(0))),
    ),
    #(
      "list-fold",
      genesis.builtin_list_fold(),
      f([f([v(1)], f([v(0)], v(1))), v(1), bt.list_of(v(0))], v(1)),
    ),
    #(
      "list-append",
      genesis.builtin_list_append(),
      f([bt.list_of(v(0)), bt.list_of(v(0))], bt.list_of(v(0))),
    ),
    #(
      "list-flatten",
      genesis.builtin_list_flatten(),
      f([bt.list_of(bt.list_of(v(0)))], bt.list_of(v(0))),
    ),
    #(
      "list-member?",
      genesis.builtin_list_member(),
      f([v(0), bt.list_of(v(0))], int()),
    ),
    #(
      "range",
      genesis.builtin_list_range(),
      f([int(), int()], bt.list_of(int())),
    ),
    #("list-sort", genesis.builtin_list_sort(), bt.host_value()),
    #("pair", genesis.builtin_pair(), bt.host_value()),
    #("fst", genesis.builtin_fst(), f([bt.pair_of(v(0), v(1))], v(0))),
    #("snd", genesis.builtin_snd(), f([bt.pair_of(v(0), v(1))], v(1))),
    #("left", genesis.builtin_left(), f([v(0)], bt.either_of(v(0), v(1)))),
    #("right", genesis.builtin_right(), f([v(1)], bt.either_of(v(0), v(1)))),
    #("dict-new", genesis.builtin_dict_new(), f([], bt.dict_of(v(0), v(1)))),
    #(
      "dict-get",
      genesis.builtin_dict_get(),
      f([bt.dict_of(v(0), v(1)), v(0)], bt.host_value()),
    ),
    #(
      "dict-set",
      genesis.builtin_dict_set(),
      f([bt.dict_of(v(0), v(1)), v(0), v(1)], bt.dict_of(v(0), v(1))),
    ),
    #(
      "dict-keys",
      genesis.builtin_dict_keys(),
      f([bt.dict_of(v(0), v(1))], bt.list_of(v(0))),
    ),
    #("set-new", genesis.builtin_set_new(), f([], bt.set_of(v(0)))),
    #(
      "set-insert",
      genesis.builtin_set_insert(),
      f([bt.set_of(v(0)), v(0)], bt.set_of(v(0))),
    ),
    #("json-parse", genesis.builtin_json_parse(), f([text()], bt.host_value())),
    #("http-get", genesis.builtin_http_get(), host([text()], text(), "Http")),
    #("file-read", genesis.builtin_file_read(), host([text()], text(), "File")),
  ]
}

fn is_host_entry(name: String) -> Bool {
  case name {
    "read_line"
    | "spawn"
    | "self"
    | "send"
    | "recv"
    | "sleep"
    | "now"
    | "http-get"
    | "file-read" -> True
    _ -> False
  }
}

pub fn is_host_ref(ref: DefinitionRef) -> Bool {
  list.any(entries(), fn(entry) {
    let #(name, known, _) = entry
    let effectful = is_host_entry(name)
    effectful && { known == ref || bt.named(name) == ref }
  })
}
