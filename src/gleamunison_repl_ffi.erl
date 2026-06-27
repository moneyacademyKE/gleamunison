-module(gleamunison_repl_ffi).
-export([eval_module/1, read_line/1]).

eval_module(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end,
    ConsoleHandler = {<<"m_74eafa15">>, #{
        0 => fun([Arg], Cont) ->
            case is_binary(Arg) of
                true -> io:format("~s~n", [Arg]);
                false -> io:format("~p~n", [Arg])
            end,
            Cont(0)
        end
    }},
    StateHandler = {<<"m_fe60582e">>, #{
        0 => fun([Key], Cont) ->
            Val = case erlang:get({state_val, Key}) of
                undefined -> <<"">>;
                V -> V
            end,
            Cont(Val)
        end,
        1 => fun([Key, Val], Cont) ->
            erlang:put({state_val, Key}, Val),
            Cont(Val)
        end
    }},
    try
        Val = gleamunison_effets:handle_comp(ConsoleHandler, fun() ->
            gleamunison_effets:handle_comp(StateHandler, fun() ->
                ModuleAtom:'$eval'()
            end)
        end),
        {ok, list_to_binary(io_lib:format("~tp", [Val]))}
    catch
        Class:Reason:Stacktrace ->
            {error, list_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stacktrace]))}
    end.

read_line(_Prompt) ->
    case io:get_line('') of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line when is_list(Line) -> {ok, unicode:characters_to_binary(Line)};
        Line when is_binary(Line) -> {ok, Line}
    end.
