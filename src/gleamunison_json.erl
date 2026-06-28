-module(gleamunison_json).
-export([encode/1, decode/1]).

encode(Term) ->
    try
        {ok, iolist_to_binary(build_json(Term))}
    catch
        error:_ -> {error, <<"encode error">>}
    end.

decode(Bin) when is_binary(Bin) ->
    try json:decode(Bin) of
        {ok, Term} -> {ok, erl_to_gleam(Term)};
        {error, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
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
    Encoded = escape_json_string(Value),
    <<$", Encoded/binary, $">>;
build_json(true) -> <<"true">>;
build_json(false) -> <<"false">>;
build_json(null) -> <<"null">>;
build_json(Value) when is_list(Value) ->
    Parts = [build_json(V) || V <- Value],
    <<$[, (binary:join(Parts, <<",">>))/binary, $]>>;
build_json(Value) when is_map(Value) ->
    Parts = [begin
        KJson = <<$", (escape_json_string(K))/binary, $">>,
        VJson = build_json(V),
        <<KJson/binary, $:, VJson/binary>>
    end || {K, V} <- maps:to_list(Value)],
    <<${, (binary:join(Parts, <<",">>))/binary, $}>>.

escape_json_string(Bin) when is_binary(Bin) ->
    escape_json_char(Bin, <<>>).

escape_json_char(<<>>, Acc) -> Acc;
escape_json_char(<<$", Rest/binary>>, Acc) -> escape_json_char(Rest, <<Acc/binary, "\\\"">>);
escape_json_char(<<$\\, Rest/binary>>, Acc) -> escape_json_char(Rest, <<Acc/binary, "\\\\">>);
escape_json_char(<<$\n, Rest/binary>>, Acc) -> escape_json_char(Rest, <<Acc/binary, "\\n">>);
escape_json_char(<<$\t, Rest/binary>>, Acc) -> escape_json_char(Rest, <<Acc/binary, "\\t">>);
escape_json_char(<<C, Rest/binary>>, Acc) -> escape_json_char(Rest, <<Acc/binary, C>>).
