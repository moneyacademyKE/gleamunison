import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef}

pub type BootstrapType {
  BTInt
  BTFloat
  BTText
  BTList
  BTVar(String)
}

pub type BootstrapOp {
  BOp(name: String, inputs: List(BootstrapType), output: BootstrapType)
}

pub type BootstrapDef {
  BAbility(name: String, ops: List(BootstrapOp))
  BTerm(name: String, ref: DefinitionRef)
}

pub fn get_init_defs_data() -> List(BootstrapDef) {
  [
    BAbility("Console", [BOp("print", [BTText], BTInt)]),
    BAbility("State", [
      BOp("get", [BTText], BTText),
      BOp("set", [BTText, BTText], BTText),
    ]),
    BAbility("Math", [
      BOp("add", [BTInt, BTInt], BTInt),
      BOp("sub", [BTInt, BTInt], BTInt),
      BOp("mul", [BTInt, BTInt], BTInt),
    ]),
    BAbility("Show", [BOp("show", [BTVar("a")], BTText)]),
    BAbility("Remote", [
      BOp("forkAt", [BTVar("location"), BTVar("a")], BTVar("task")),
      BOp("await", [BTVar("task")], BTVar("a")),
      BOp("here", [], BTVar("location")),
    ]),
    BTerm("add", genesis.builtin_int_add()),
    BTerm("+", genesis.builtin_int_add()),
    BTerm("read_line", genesis.builtin_io_read_line()),
    BTerm("spawn", genesis.builtin_process_spawn()),
    BTerm("self", genesis.builtin_process_self()),
    BTerm("send", genesis.builtin_process_send()),
    BTerm("recv", genesis.builtin_process_recv()),
    BTerm("sleep", genesis.builtin_timer_sleep()),
    BTerm("now", genesis.builtin_timer_now()),
    BTerm("sub", genesis.builtin_sub()),
    BTerm("mul", genesis.builtin_mul()),
    BTerm("div", genesis.builtin_div()),
    BTerm("mod", genesis.builtin_mod()),
    BTerm("eq?", genesis.builtin_eq()),
    BTerm("lt?", genesis.builtin_lt()),
    BTerm("gt?", genesis.builtin_gt()),
    BTerm("and", genesis.builtin_and()),
    BTerm("or", genesis.builtin_or()),
    BTerm("not", genesis.builtin_not()),
    BTerm("string-concat", genesis.builtin_string_concat()),
    BTerm("string-length", genesis.builtin_string_length()),
    BTerm("string-contains?", genesis.builtin_string_contains()),
    BTerm("string-slice", genesis.builtin_string_slice()),
    BTerm("string-upcase", genesis.builtin_string_upcase()),
    BTerm("string-downcase", genesis.builtin_string_downcase()),
    BTerm("string-replace", genesis.builtin_string_replace()),
    BTerm("string-split", genesis.builtin_string_split()),
    BTerm("string-trim", genesis.builtin_string_trim()),
    BTerm("string->int", genesis.builtin_string_to_int()),
    BTerm("list-length", genesis.builtin_list_length()),
    BTerm("list-reverse", genesis.builtin_list_reverse()),
    BTerm("list-map", genesis.builtin_list_map()),
    BTerm("list-filter", genesis.builtin_list_filter()),
    BTerm("list-fold", genesis.builtin_list_fold()),
    BTerm("list-append", genesis.builtin_list_append()),
    BTerm("list-flatten", genesis.builtin_list_flatten()),
    BTerm("list-member?", genesis.builtin_list_member()),
    BTerm("range", genesis.builtin_list_range()),
    BTerm("list-sort", genesis.builtin_list_sort()),
    BTerm("pair", genesis.builtin_pair()),
    BTerm("fst", genesis.builtin_fst()),
    BTerm("snd", genesis.builtin_snd()),
    BTerm("left", genesis.builtin_left()),
    BTerm("right", genesis.builtin_right()),
    BTerm("dict-new", genesis.builtin_dict_new()),
    BTerm("dict-get", genesis.builtin_dict_get()),
    BTerm("dict-set", genesis.builtin_dict_set()),
    BTerm("set-new", genesis.builtin_set_new()),
    BTerm("set-insert", genesis.builtin_set_insert()),
    BTerm("json-parse", genesis.builtin_json_parse()),
    BTerm("http-get", genesis.builtin_http_get()),
    BTerm("file-read", genesis.builtin_file_read()),
  ]
}
