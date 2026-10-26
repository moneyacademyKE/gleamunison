-module(gleamunison_ffi).
-export([
    hash_bytes/1, hash_equal/2, hash_to_hex/1,
    compile_source/1, load_binary/2, module_available/1, module_exports/1, string_to_binary/1,
    hex_to_bytes/1,
    unload_binary/1, soft_purge_binary/1,
    binary_to_erl_literal/1,
    get_plain_args/0,
    halt_failure/0, halt_failure_code/1,
    application_version/0,
    to_dynamic/1,
    from_dynamic/1,
    rescue/1,
    stdio_binary_mode/0, stdio_read_line/0, stdio_read_chars/1, stdio_write/1,
    deny_capability/2,
    corrupt_handler_stack/1, assert_throws_corrupted_stack/1,
    render_term/1, parse_term_arg/1, term_to_json/2, json_quote/1,
    argv_to_binary/1,
    test_soft_purge_scenario/0,
    eval_expression/1,
    load_dogfood_levels/1, load_dogfood_levels_resolved/0
]).

hash_bytes(Bytes) when is_binary(Bytes) ->
    crypto:hash(sha256, Bytes).

hash_equal(A, B) when is_binary(A), is_binary(B) -> A =:= B.

hash_to_hex(Bytes) when is_binary(Bytes) ->
    [<<(hex(N bsr 4)), (hex(N band 15))>> || <<N:8>> <= Bytes].

hex(N) when N < 10 -> $0 + N;
hex(N) -> $a + N - 10.

string_to_binary(S) when is_binary(S) -> S;
string_to_binary(S) when is_list(S) -> list_to_binary(S).

%% Run a zero-arg fun and capture any raised reason as {error, Rendered}.
%% CLIs use this to turn runtime crashes (replay divergence, unhandled
%% abilities) into error values the caller can print.
rescue(F) when is_function(F, 0) ->
    try F() of
        R -> {ok, R}
    catch
        Class:Reason -> {error, iolist_to_binary(io_lib:format("~p:~p", [Class, Reason]))}
    end.

%% LSP stdio pump helpers. Binary mode matters: Content-Length counts
%% bytes, and io in list mode would miscount UTF-8 beyond ASCII.
stdio_binary_mode() ->
    io:setopts(standard_io, [binary]),
    nil.

%% One header line (through \n), or {error, nil} on EOF.
stdio_read_line() ->
    case io:get_line(standard_io, '') of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Bin when is_binary(Bin) -> {ok, Bin};
        L when is_list(L) -> {ok, unicode:characters_to_binary(L)}
    end.

%% Exactly N bytes (the message body), or {error, nil} on EOF/short read.
stdio_read_chars(N) ->
    case io:get_chars(standard_io, '', N) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Bin when is_binary(Bin) -> {ok, Bin};
        L when is_list(L) -> {ok, unicode:characters_to_binary(L)}
    end.

stdio_write(Bin) when is_binary(Bin) ->
    io:put_chars(standard_io, Bin),
    nil.

compile_source(Source) when is_binary(Source) ->
    case erl_scan:string(binary_to_list(Source)) of
        {ok, Tokens, _} ->
            case split_and_parse_forms(Tokens, [], []) of
                {ok, Forms} ->
                    case compile:forms(Forms, [binary, return]) of
                        {ok, _Mod, Bin} -> {ok, Bin};
                        {ok, _Mod, Bin, _Warnings} -> {ok, Bin};
                        {error, Errors, _Warnings} ->
                            io:format("Failed Source:~n~s~n", [Source]),
                            {error, flatten_errors(Errors)};
                        error ->
                            {error, <<"compiler failed without errors info">>}
                    end;
                {error, {parse_error, Line, Err}} ->
                    io:format("Failed Source:~n~s~n", [Source]),
                    {error, list_to_binary(io_lib:format("parse error at line ~p: ~p", [Line, Err]))};
                {error, Err} ->
                    io:format("Failed Source:~n~s~n", [Source]),
                    {error, list_to_binary(io_lib:format("parse error: ~p", [Err]))}
            end;
        {error, ErrorInfo, _} ->
            io:format("Failed Source:~n~s~n", [Source]),
            {error, list_to_binary(io_lib:format("scan error: ~p", [ErrorInfo]))}
    end;
compile_source(_) -> {error, <<"source must be binary">>}.

split_and_parse_forms([], [], Forms) ->
    {ok, lists:reverse(Forms)};
split_and_parse_forms([], CurrentForm, Forms) ->
    case erl_parse:parse_form(lists:reverse(CurrentForm)) of
        {ok, Form} -> {ok, lists:reverse([Form | Forms])};
        {error, Err} -> {error, Err}
    end;
split_and_parse_forms([ {dot, Line} = Dot | Rest ], CurrentForm, Forms) ->
    case erl_parse:parse_form(lists:reverse([Dot | CurrentForm])) of
        {ok, Form} ->
            split_and_parse_forms(Rest, [], [Form | Forms]);
        {error, Err} ->
            {error, {parse_error, Line, Err}}
    end;
split_and_parse_forms([ Tok | Rest ], CurrentForm, Forms) ->
    split_and_parse_forms(Rest, [Tok | CurrentForm], Forms).

flatten_errors(Errors) ->
    list_to_binary(lists:flatten(io_lib:format("~p", [Errors]))).

load_binary(Mod, Binary) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false when is_list(Mod) -> erlang:list_to_atom(Mod);
        false -> erlang:binary_to_atom(erlang:iolist_to_binary(Mod), utf8)
    end,
    try code:load_binary(ModuleAtom, atom_to_list(ModuleAtom) ++ ".beam", Binary) of
        {module, ModuleAtom} -> {ok, nil};
        {error, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    catch
        exit:Reason -> {error, list_to_binary(io_lib:format("~p", [Reason]))};
        _:Reason -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

%% Is a compiled module already present in this runtime? Genesis builtins ship
%% as m_*.erl sources compiled into the build and the escript archive, so a
%% definition that references one needs no store lookup.
module_available(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false when is_list(Mod) -> erlang:list_to_atom(Mod);
        false -> erlang:binary_to_atom(erlang:iolist_to_binary(Mod), utf8)
    end,
    case code:ensure_loaded(ModuleAtom) of
        {module, ModuleAtom} -> true;
        _ -> false
    end.

%% Export table of a loaded module, sorted. Locks the compiler's export
%% contract and backs introspection (`run --json` on a function).
module_exports(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false when is_list(Mod) -> erlang:list_to_atom(Mod);
        false -> erlang:binary_to_atom(erlang:iolist_to_binary(Mod), utf8)
    end,
    case code:ensure_loaded(ModuleAtom) of
        {module, ModuleAtom} ->
            Exports = lists:sort(ModuleAtom:module_info(exports)),
            %% module_info/{0,1} ride on every BEAM module; they are never
            %% definition exports, so they are noise for introspection.
            DefExports = [{atom_to_binary(F, utf8), A} || {F, A} <- Exports, F =/= module_info],
            {ok, DefExports};
        _ ->
            {error, <<"module not loaded">>}
    end.

hex_to_bytes(Hex) when is_binary(Hex) ->
    try {ok, binary:decode_hex(Hex)}
    catch error:badarg -> {error, <<"invalid hex: expected an even number of hexadecimal digits">>}
    end;
hex_to_bytes(_) -> {error, <<"invalid hex: expected a binary string">>}.

unload_binary(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end,
    %% A previous reload may already have left an old version. Retire it before
    %% making the current version old, then finish the unload; delete-first
    %% reports "must be purged" and leaves the supposedly unloaded code behind.
    code:purge(ModuleAtom),
    code:delete(ModuleAtom),
    code:purge(ModuleAtom),
    {ok, nil}.

soft_purge_binary(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end,
    code:delete(ModuleAtom),
    Res = code:soft_purge(ModuleAtom),
    {ok, Res}.

%% @private Test helpers
corrupt_handler_stack(Val) ->
    erlang:put({gleamunison_handlers}, Val), ok.

assert_throws_corrupted_stack(Fun) ->
    try
        Fun(), error(did_not_throw)
    catch
        error:{corrupted_handler_stack, _} -> ok;
        error:{invalid_handler_stack, _} -> ok;
        error:{invalid_handler, _} -> ok
    after
        %% The probe corrupts the stack BEFORE calling us, so the value on
        %% entry is already poison. Tests share the BEAM process: leave a
        %% valid empty stack behind or every later effects test fails.
        erlang:put({gleamunison_handlers}, {trusted_stack, []})
    end.

test_soft_purge_scenario() ->
    Source = <<"-module('m_purge_test').\n-export([loop/0]).\nloop() -> timer:sleep(1000), loop().\n">>,
    {ok, Bin} = compile_source(Source),
    {module, m_purge_test} = code:load_binary(m_purge_test, "nofile", Bin),
    Pid = spawn(fun() -> m_purge_test:loop() end),
    timer:sleep(50),
    code:delete(m_purge_test),
    PurgeRes1 = code:soft_purge(m_purge_test),
    exit(Pid, kill),
    timer:sleep(50),
    PurgeRes2 = code:soft_purge(m_purge_test),
    code:delete(m_purge_test),
    code:purge(m_purge_test),
    {ok, {PurgeRes1, PurgeRes2}}.

%% Render a runtime value the way the REPL does. One renderer for the CLI text
%% path and the log, so a value never has two spellings. UTF-8 text renders as
%% text; `gleamunison_render` owns that decision.
render_term(Term) ->
    gleamunison_render:term(Term).

%% A runtime value as JSON, for `run --json`. Native where the shape is
%% unambiguous (numbers, text, booleans, nil, lists), tagged where the language
%% has a constructor ({tag, data}) and opaque where JSON has no honest
%% representation (functions, pids, non-UTF8 binaries, maps). Depth is capped
%% so a cyclic or huge term cannot hang a CLI.
-define(JSON_MAX_DEPTH, 16).

term_to_json(Term, Depth) ->
    iolist_to_binary(term_to_json_iolist(Term, Depth)).

term_to_json_iolist(_Term, Depth) when Depth > ?JSON_MAX_DEPTH ->
    ["{\"truncated\":", integer_to_list(Depth), "}"];
term_to_json_iolist(Term, _Depth) when is_integer(Term) ->
    integer_to_binary(Term);
term_to_json_iolist(Term, _Depth) when is_float(Term) ->
    float_to_binary(Term, [short]);
term_to_json_iolist(true, _Depth) -> <<"true">>;
term_to_json_iolist(false, _Depth) -> <<"false">>;
term_to_json_iolist(nil, _Depth) -> <<"null">>;
term_to_json_iolist(Term, _Depth) when is_binary(Term) ->
    case unicode:characters_to_binary(Term) of
        Term -> json_string(Term);
        _ -> opaque(Term)
    end;
term_to_json_iolist(Term, _Depth) when is_atom(Term) ->
    json_string(atom_to_binary(Term, utf8));
term_to_json_iolist(Term, Depth) when is_list(Term) ->
    case is_proper_list(Term) of
        true ->
            [ "["
            , lists:join(",", [term_to_json_iolist(E, Depth + 1) || E <- Term])
            , "]" ];
        false ->
            %% An improper list has no JSON shape; name it rather than lie.
            opaque(Term)
    end;
term_to_json_iolist(Term, Depth) when is_tuple(Term) ->
    case tuple_to_list(Term) of
        [Tag | Args] when is_atom(Tag), Args =/= [] ->
            [ "{\"tag\":", json_string(atom_to_binary(Tag, utf8))
            , ",\"data\":["
            , lists:join(",", [term_to_json_iolist(A, Depth + 1) || A <- Args])
            , "]}"
            ];
        Elements ->
            [ "{\"tuple\":["
            , lists:join(",", [term_to_json_iolist(E, Depth + 1) || E <- Elements])
            , "]}"
            ]
    end;
term_to_json_iolist(Term, Depth) when is_map(Term) ->
    Pairs = lists:sort(maps:to_list(Term)),
    [ "{\"map\":["
    , lists:join(",", [
        ["{\"key\":", term_to_json_iolist(K, Depth + 1),
         ",\"value\":", term_to_json_iolist(V, Depth + 1), "}"]
        || {K, V} <- Pairs
      ])
    , "]}"
    ];
term_to_json_iolist(Term, _Depth) ->
    opaque(Term).

is_proper_list([]) -> true;
is_proper_list([_ | Rest]) -> is_proper_list(Rest);
is_proper_list(_) -> false.

opaque(Term) ->
    [ "{\"opaque\":"
    , json_string(list_to_binary(io_lib:format("~tp", [Term])))
    , "}"
    ].

json_quote(Bin) when is_binary(Bin) ->
    %% Gleam String is a binary: flatten the escaped iolist at the boundary.
    iolist_to_binary(json_string(Bin)).

json_string(Bin) when is_binary(Bin) ->
    [ "\""
    , [escape_char(C) || <<C>> <= Bin]
    , "\""
    ].

escape_char($") -> "\\\"";
escape_char($\\) -> "\\\\";
escape_char($\n) -> "\\n";
escape_char($\r) -> "\\r";
escape_char($\t) -> "\\t";
escape_char(C) when C < 16#20 ->
    io_lib:format("\\u~4.16.0b", [C]);
escape_char(C) when C < 16#80 ->
    <<C>>;
escape_char(C) ->
    %% Pass multi-byte UTF-8 through untouched; JSON is UTF-8.
    <<C>>.

%% Parse one CLI argument into an Erlang term. The language's Text is a
%% BitArray, so a double-quoted string becomes a binary rather than an Erlang
%% charlist. Integers, floats, true/false/nil and quoted atoms parse as
%% themselves; a bare word parses as an atom only when it is one of those three
%% (anything else falls back to raw text at the call site, which is what a
%% user typing `hello` means). erl_parse:parse_term/1 demands a terminating
%% dot, so one is appended rather than required from the user.
parse_term_arg(Arg) when is_binary(Arg) ->
    try
        case erl_scan:string(binary_to_list(Arg) ++ ".") of
            {ok, [{string, _, Chars}, {dot, _}], _} ->
                %% Quoted text: the language's Text type is a binary.
                {ok, list_to_binary(Chars)};
            {ok, Tokens, _} ->
                case erl_parse:parse_term(Tokens) of
                    {ok, Term} when is_atom(Term) ->
                        case Term of
                            true -> {ok, true};
                            false -> {ok, false};
                            nil -> {ok, nil};
                            _ -> {error, nil}
                        end;
                    {ok, Term} -> {ok, Term};
                    {error, _} -> {error, nil}
                end;
            {error, _, _} -> {error, nil}
        end
    catch
        _:_ -> {error, nil}
    end.

binary_to_erl_literal(Bin) when is_binary(Bin) ->
    Segments = [integer_to_list(X) || <<X>> <= Bin],
    erlang:iolist_to_binary(["<<", string:join(Segments, ", "), ">>"]).

get_plain_args() ->
    [argv_to_binary(A) || A <- init:get_plain_arguments()].

%% Erlang hands plain arguments over as latin-1 codepoints: the UTF-8 bytes
%% 195,169 (é) arrive as the single codepoint 233, and `list_to_binary/1` then
%% writes 0xE9 — not valid UTF-8. Every caller downstream (the term parser, the
%% Text type) then sees mojibake. Re-encode the codepoints as UTF-8 to recover
%% the bytes the shell actually passed. A list already carrying codepoints
%% above 255 came in as unicode (`+pc unicode`) and needs no latin-1 step.
argv_to_binary(A) when is_binary(A) ->
    A;
argv_to_binary(A) when is_list(A) ->
    Encoding = case lists:all(fun(C) -> is_integer(C) andalso C >= 0 andalso C =< 255 end, A) of
        true -> latin1;
        false -> unicode
    end,
    case unicode:characters_to_binary(A, Encoding, utf8) of
        Bin when is_binary(Bin) -> Bin;
        _ -> list_to_binary(A)
    end.

halt_failure() ->
    erlang:halt(1).

%% A CLI that distinguishes "refused" from "could not resolve" needs more than
%% success/failure: the exit code is the contract a script reads.
halt_failure_code(Code) when is_integer(Code) ->
    erlang:halt(Code).

application_version() ->
    case application:get_key(gleamunison, vsn) of
        {ok, Vsn} when is_list(Vsn) -> list_to_binary(Vsn);
        {ok, Vsn} when is_binary(Vsn) -> Vsn;
        undefined -> <<"development">>
    end.

to_dynamic(X) -> X.

from_dynamic(X) -> X.

%% Structured denial for capability-scoped execution: a distinct, matchable
%% error term so sandbox runners can catch it apart from unhandled_ability.
deny_capability(AbilityKey, OpIdx) ->
    erlang:error({capability_denied, AbilityKey, OpIdx}).

eval_expression(Expr) ->
    gleamunison_ffi_io:eval_expression(Expr).

load_dogfood_levels(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> parse_dogfood_levels(Bin);
        {error, Reason} -> {error, list_to_binary(io_lib:format("File error: ~p", [Reason]))}
    end.

%% Resolution order: the escript archive, the packaged priv dir, then the
%% repository copy. A missing file is an error, never an empty level list:
%% a CLI that reports success for zero levels is worse than one that fails.
load_dogfood_levels_resolved() ->
    case gleamunison_archive:read_embedded(<<"priv/dogfood/dogfood_data.json">>) of
        {ok, Bin} -> parse_dogfood_levels(Bin);
        {error, _} -> load_dogfood_levels_from_disk("priv/dogfood/dogfood_data.json", "src/dogfood_data.json")
    end.

load_dogfood_levels_from_disk(Packaged, Repo) ->
    case file:read_file(Packaged) of
        {ok, Bin} -> parse_dogfood_levels(Bin);
        {error, _} ->
            case file:read_file(Repo) of
                {ok, Bin} -> parse_dogfood_levels(Bin);
                {error, Reason} ->
                    {error, list_to_binary(io_lib:format("level data not found: ~p", [Reason]))}
            end
    end.

parse_dogfood_levels(Bin) ->
    try json:decode(Bin) of
        List -> {ok, [map_to_level(M) || M <- List]}
    catch
        Class:Reason ->
            {error, list_to_binary(io_lib:format("JSON error: ~p:~p", [Class, Reason]))}
    end.

map_to_level(#{<<"n">> := N, <<"t">> := T, <<"args">> := Args}) ->
    case T of
        <<"CompileInt">> -> {compile_int, N, to_integer(lists:nth(1, Args))};
        <<"CompileFloat">> -> {compile_float, N, to_float(lists:nth(1, Args))};
        <<"CompileText">> -> {compile_text, N, lists:nth(1, Args)};
        <<"LambdaApply">> -> {lambda_apply, N, to_integer(lists:nth(1, Args))};
        <<"CompileLet">> -> {compile_let, N, to_integer(lists:nth(1, Args))};
        <<"CompileList">> -> {compile_list, N, [to_integer(X) || X <- Args]};
        <<"Elaborate">> -> {elaborate, N, lists:nth(1, Args)};
        <<"LoaderLimit">> -> {loader_limit, N, to_integer(lists:nth(1, Args)), to_integer(lists:nth(2, Args))};
        <<"CodebaseInsert">> -> {codebase_insert, N, to_integer(lists:nth(1, Args)), to_integer(lists:nth(2, Args))};
        <<"StorageStress">> -> {storage_stress, N, to_integer(lists:nth(1, Args))};
        <<"CrossRef">> -> {cross_ref, N, to_integer(lists:nth(1, Args))};
        <<"EffectsHandle">> -> {effects_handle, N, to_integer(lists:nth(1, Args))};
        <<"ElabUnitAbilities">> -> {elab_unit_abilities, N, to_integer(lists:nth(1, Args))};
        <<"Typecheck">> -> {typecheck, N, to_integer(lists:nth(1, Args)), to_integer(lists:nth(2, Args))};
        <<"LoaderLoaded">> -> {loader_loaded, N, to_integer(lists:nth(1, Args))};
        <<"HashDistinct">> -> {hash_distinct, N, to_integer(lists:nth(1, Args)), to_integer(lists:nth(2, Args))};
        <<"InsertRaw">> -> {insert_raw, N};
        <<"ReplEval">> -> {repl_eval, N, lists:nth(1, Args)};
        <<"Serialize">> -> {serialize, N, to_integer(lists:nth(1, Args))};
        <<"EmptyList">> -> {empty_list, N};
        <<"ElabError">> -> {elab_error, N, lists:nth(1, Args)};
        <<"CompileConstruct">> -> {compile_construct, N};
        <<"TypePretty">> -> {type_pretty, N, lists:nth(1, Args), lists:nth(2, Args)};
        <<"InferTerm">> -> {infer_term, N, lists:nth(1, Args), lists:nth(2, Args)}
    end.

to_integer(Val) when is_integer(Val) -> Val;
to_integer(Val) when is_binary(Val) -> binary_to_integer(Val).

to_float(Val) when is_float(Val) -> Val;
to_float(Val) when is_integer(Val) -> erlang:float(Val);
to_float(Val) when is_binary(Val) ->
    case binary:match(Val, <<".">>) of
        nomatch -> erlang:float(binary_to_integer(Val));
        _ -> binary_to_float(Val)
    end.
