-module(gleamunison_json).
-export([encode/1, decode/1]).

encode(Term) ->
    try
        {ok, iolist_to_binary(build_json(Term))}
    catch
        error:Reason:Stack ->
            %% Name the real failure: a swallowed reason is a debugging
            %% tax paid on every platform where encode misbehaves (bk-19fe).
            {error, unicode:characters_to_binary(io_lib:format(
                "encode error: ~p at ~p", [Reason, lists:sublist(Stack, 2)]))}
    end.

decode(Bin) when is_binary(Bin) ->
    try json:decode(Bin) of
        Term -> {ok, erl_to_gleam(Term)}
    catch
        _:Reason -> {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

erl_to_gleam(Value) when is_integer(Value) -> Value;
erl_to_gleam(Value) when is_float(Value) -> Value;
erl_to_gleam(Value) when is_binary(Value) -> Value;
erl_to_gleam(Value) when is_boolean(Value) -> Value;
erl_to_gleam(null) -> null;
erl_to_gleam(Value) when is_list(Value) ->
    case is_proplist(Value) of
        true ->
            maps:from_list([{K, erl_to_gleam(V)} || {K, V} <- Value]);
        false ->
            [erl_to_gleam(V) || V <- Value]
    end;
erl_to_gleam(Value) when is_map(Value) ->
    maps:map(fun(_K, V) -> erl_to_gleam(V) end, Value).

is_proplist([{K, _} | _]) when is_binary(K); is_list(K); is_atom(K) -> true;
is_proplist(_) -> false.

build_json(Value) when is_integer(Value) -> integer_to_binary(Value);
build_json(Value) when is_float(Value) -> float_to_binary(Value);
build_json(Value) when is_binary(Value) ->
    %% The FFI escaper is the single owner (quotes included): it escapes
    %% \r and every C0 control as \uXXXX, which the local escaper this
    %% replaced passed through raw, producing invalid JSON (bk-5f59).
    gleamunison_ffi:json_quote(Value);
build_json(true) -> <<"true">>;
build_json(false) -> <<"false">>;
build_json(null) -> <<"null">>;
build_json(Value) when is_list(Value) ->
    Parts = [build_json(V) || V <- Value],
    <<$[, (iolist_to_binary(lists:join(<<",">>, Parts)))/binary, $]>>;
build_json(Value) when is_map(Value) ->
    Parts = [begin
        KJson = gleamunison_ffi:json_quote(K),
        VJson = build_json(V),
        <<KJson/binary, $:, VJson/binary>>
    end || {K, V} <- maps:to_list(Value)],
    <<${, (iolist_to_binary(lists:join(<<",">>, Parts)))/binary, $}>>.
