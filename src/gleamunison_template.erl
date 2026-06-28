-module(gleamunison_template).
-export([interpolate/2, safe_string/1]).

interpolate(Template, Vars) when is_binary(Template), is_list(Vars) ->
    try do_interpolate(Template, Vars, <<>>) of
        Result -> {ok, Result}
    catch
        throw:{template_error, Reason} -> {error, Reason}
    end.

do_interpolate(<<"{{", Rest/binary>>, Vars, Acc) ->
    case binary:split(Rest, <<"}}">>) of
        [VarName, After] ->
            Var = binary_to_list(VarName),
            Value = case lists:keyfind(Var, 1, Vars) of
                {Var, V} -> safe_to_binary(V);
                false -> throw({template_error, list_to_binary("undefined variable: " ++ Var)})
            end,
            do_interpolate(After, Vars, <<Acc/binary, Value/binary>>);
        _ ->
            throw({template_error, <<"unclosed {{">>})
    end;
do_interpolate(<<C, Rest/binary>>, Vars, Acc) ->
    do_interpolate(Rest, Vars, <<Acc/binary, C>>);
do_interpolate(<<>>, _Vars, Acc) -> Acc.

safe_to_binary(Val) when is_binary(Val) -> safe_string(Val);
safe_to_binary(Val) when is_integer(Val) -> integer_to_binary(Val);
safe_to_binary(Val) when is_float(Val) -> float_to_binary(Val);
safe_to_binary(Val) when is_boolean(Val) -> atom_to_binary(Val);
safe_to_binary(Val) -> list_to_binary(io_lib:format("~p", [Val])).

safe_string(Bin) when is_binary(Bin) ->
    list_to_binary([escape_char(C) || <<C>> <= Bin]).

escape_char($<) -> <<"&lt;">>;
escape_char($>) -> <<"&gt;">>;
escape_char($&) -> <<"&amp;">>;
escape_char($") -> <<"&quot;">>;
escape_char($') -> <<"&#39;">>;
escape_char(C) -> <<C>>.
