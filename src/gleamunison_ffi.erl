-module(gleamunison_ffi).
-export([
    hash_bytes/1, hash_equal/2, hash_to_hex/1,
    compile_source/1, load_binary/2, string_to_binary/1,
    hex_to_bytes/1,
    unload_binary/1, soft_purge_binary/1,
    binary_to_erl_literal/1,
    get_plain_args/0,
    to_dynamic/1,
    corrupt_handler_stack/1, assert_throws_corrupted_stack/1,
    test_soft_purge_scenario/0,
    eval_expression/1,
    load_dogfood_levels/1
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
                    {error, list_to_binary(io_lib:format("parse error at line ~p: ~p", [Line, Err]))};
                {error, Err} ->
                    {error, list_to_binary(io_lib:format("parse error: ~p", [Err]))}
            end;
        {error, ErrorInfo, _} ->
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

hex_to_bytes(Hex) when is_binary(Hex) ->
    binary:decode_hex(Hex).

unload_binary(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end,
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

binary_to_erl_literal(Bin) when is_binary(Bin) ->
    Segments = [integer_to_list(X) || <<X>> <= Bin],
    erlang:iolist_to_binary(["<<", string:join(Segments, ", "), ">>"]).

get_plain_args() ->
    [list_to_binary(A) || A <- init:get_plain_arguments()].

to_dynamic(X) -> X.

eval_expression(Expr) ->
    gleamunison_ffi_io:eval_expression(Expr).

load_dogfood_levels(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            try json:decode(Bin) of
                List -> {ok, [map_to_level(M) || M <- List]}
            catch
                Class:Reason ->
                    {error, list_to_binary(io_lib:format("JSON error: ~p:~p", [Class, Reason]))}
            end;
        {error, Reason} -> {error, list_to_binary(io_lib:format("File error: ~p", [Reason]))}
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
