-module(gleamunison_ffi).
-export([
    hash_bytes/1, hash_equal/2, hash_to_hex/1,
    compile_source/1, load_binary/2,
    string_to_binary/1
]).

%% --- Hash ---
hash_bytes(Bytes) when is_binary(Bytes) ->
    <<(erlang:phash2(Bytes)):32/big-unsigned-integer>>.

hash_equal(A, B) when is_binary(A), is_binary(B) -> A =:= B.

hash_to_hex(Bytes) when is_binary(Bytes) ->
    [<<(hex(N bsr 4)), (hex(N band 15))>> || <<N:8>> <= Bytes].

hex(N) when N < 10 -> $0 + N;
hex(N) -> $a + N - 10.

%% --- String to binary ---
string_to_binary(S) when is_binary(S) -> S;
string_to_binary(S) when is_list(S) -> list_to_binary(S).

%% --- Compilation ---
compile_source(Source) when is_binary(Source) ->
    ModuleName = case Source of
        <<"-module('", Rest/binary>> ->
            case binary:split(Rest, <<"'">>) of
                [Name, _] -> Name;
                _ -> <<"unknown">>
            end;
        _ -> <<"unknown">>
    end,
    TmpDir = case os:getenv("TMPDIR") of
        false -> "/tmp";
        Dir -> Dir
    end,
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
            {ok, _Mod, Bin} when is_binary(Bin), byte_size(Bin) > 0 ->
                {ok, Bin};
            {ok, _Mod, _Other} ->
                case file:read_file(BeamFile) of
                    {ok, Bin} -> {ok, Bin};
                    {error, R} -> {error, list_to_binary(io_lib:format("read2 failed: ~p", [R]))}
                end;
            {ok, _Mod, Bin, _Ws} when is_binary(Bin), byte_size(Bin) > 0 ->
                {ok, Bin};
            {ok, _Mod, _Other, _Ws} ->
                case file:read_file(BeamFile) of
                    {ok, Bin} -> {ok, Bin};
                    {error, R} -> {error, list_to_binary(io_lib:format("read3 failed: ~p", [R]))}
                end;
            {error, Errors, _Ws} ->
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

%% --- Code loading ---
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
