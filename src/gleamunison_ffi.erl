-module(gleamunison_ffi).
-export([
    hash_bytes/1, hash_equal/2, hash_to_hex/1,
    compile_source/1, load_binary/2, string_to_binary/1,
    hex_to_bytes/1,
    unload_binary/1, soft_purge_binary/1,
    corrupt_handler_stack/1, assert_throws_corrupted_stack/1,
    test_soft_purge_scenario/0,
    binary_to_erl_literal/1,
    get_plain_args/0,
    to_dynamic/1
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
    ModuleName = case Source of
        <<"-module('", Rest/binary>> ->
            case binary:split(Rest, <<"'">>) of
                [Name, _] -> Name;
                _ -> <<"unknown">>
            end;
        _ -> <<"unknown">>
    end,
    TmpDir = case os:getenv("TMPDIR") of false -> "/tmp"; Dir -> Dir end,
    TmpFile = filename:join(TmpDir, binary_to_list(ModuleName) ++ ".erl"),
    BeamFile = filename:rootname(TmpFile) ++ ".beam",
    try
        ok = file:write_file(TmpFile, Source),
        case compile:file(TmpFile, [{outdir, TmpDir}, return]) of
            {ok, _Mod} ->
                case file:read_file(BeamFile) of
                    {ok, Bin} -> {ok, Bin};
                    {error, R} -> {error, list_to_binary(io_lib:format("read failed: ~p", [R]))}
                end;
            {ok, _Mod, Bin} when is_binary(Bin), byte_size(Bin) > 0 -> {ok, Bin};
            {ok, _Mod, _Other} ->
                case file:read_file(BeamFile) of
                    {ok, Bin} -> {ok, Bin};
                    {error, R} -> {error, list_to_binary(io_lib:format("read2 failed: ~p", [R]))}
                end;
            {ok, _Mod, Bin, _Ws} when is_binary(Bin), byte_size(Bin) > 0 -> {ok, Bin};
            {ok, _Mod, _Other, _Ws} ->
                case file:read_file(BeamFile) of
                    {ok, Bin} -> {ok, Bin};
                    {error, R} -> {error, list_to_binary(io_lib:format("read3 failed: ~p", [R]))}
                end;
            {error, Errors, _Ws} ->
                io:format("Failed Source:~n~s~n", [Source]),
                {error, flatten_errors(Errors)}
        end
    after
        catch file:delete(TmpFile),
        catch file:delete(BeamFile),
        ok
    end;
compile_source(_) -> {error, <<"source must be binary">>}.

flatten_errors(Errors) ->
    list_to_binary(lists:flatten(io_lib:format("~p", [Errors]))).

load_binary(Mod, Binary) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false when is_list(Mod) -> erlang:list_to_atom(Mod);
        false -> erlang:binary_to_atom(erlang:iolist_to_binary(Mod), utf8)
    end,
    case catch code:load_binary(ModuleAtom, atom_to_list(ModuleAtom) ++ ".beam", Binary) of
        {module, ModuleAtom} -> {ok, nil};
        {'EXIT', Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))};
        {error, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
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
