-module(gleamunison_repl_ffi).
-export([eval_module/1, read_line/1]).

eval_module(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end,
    ConsoleHandler = {<<"m_74eafa15">>, #{
        0 => fun([Text], Cont) ->
            io:format("~s~n", [Text]),
            Cont(0)
        end
    }},
    try
        Val = gleamunison_effets:handle_comp(ConsoleHandler, fun() -> ModuleAtom:'$eval'() end),
        {ok, list_to_binary(io_lib:format("~p", [Val]))}
    catch
        Class:Reason:Stacktrace ->
            {error, list_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stacktrace]))}
    end.

read_line(Prompt) ->
    case io:get_line(Prompt) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line when is_list(Line) -> {ok, list_to_binary(Line)};
        Line when is_binary(Line) -> {ok, Line}
    end.
