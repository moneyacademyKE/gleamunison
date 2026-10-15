-module(gleamunison_repl_ffi).
-export([eval_module/1, eval_module_bare/1, read_line/1]).

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
    MathHandler = {<<"m_b514a6e3">>, #{
        0 => fun([X, Y], Cont) -> Cont(X + Y) end,
        1 => fun([X, Y], Cont) -> Cont(X - Y) end,
        2 => fun([X, Y], Cont) -> Cont(X * Y) end
    }},
    ShowHandler = {<<"m_d17eaeb6">>, #{
        0 => fun([Val], Cont) ->
            Str = case is_binary(Val) of
                true -> << "\"", Val/binary, "\"" >>;
                false -> list_to_binary(io_lib:format("~tp", [Val]))
            end,
            Cont(Str)
        end
    }},
    RemoteHandler = {<<"m_ffa98e02">>, #{
        0 => fun([Location, Computation], Cont) ->
            Node = erlang:binary_to_atom(Location, utf8),
            Self = self(),
            Pid = spawn_link(Node, fun() ->
                Res = case is_function(Computation, 0) of
                    true -> Computation();
                    false -> Computation(nil)
                end,
                Self ! {task_result, self(), Res}
            end),
            Cont(Pid)
        end,
        1 => fun([Pid], Cont) ->
            receive
                {task_result, Pid, Res} -> Cont(Res)
            end
        end,
        2 => fun([], Cont) ->
            Cont(atom_to_binary(node(), utf8))
        end
    }},
    LLMHandler = {<<"m_a12979b5">>, #{
        0 => fun([Prompt], Cont) ->
            case gleamunison@llm:complete_env(Prompt) of
                {ok, Text} -> Cont(Text);
                {error, Msg} -> erlang:error({llm_failed, Msg})
            end
        end,
        1 => fun([System, Prompt], Cont) ->
            Joined = <<System/binary, "\n\n", Prompt/binary>>,
            case gleamunison@llm:complete_env(Joined) of
                {ok, Text} -> Cont(Text);
                {error, Msg} -> erlang:error({llm_failed, Msg})
            end
        end
    }},
    try
        Val = gleamunison_effets:handle_comp(ConsoleHandler, fun() ->
            gleamunison_effets:handle_comp(StateHandler, fun() ->
                gleamunison_effets:handle_comp(MathHandler, fun() ->
                    gleamunison_effets:handle_comp(ShowHandler, fun() ->
                        gleamunison_effets:handle_comp(RemoteHandler, fun() ->
                            gleamunison_effets:handle_comp(LLMHandler, fun() ->
                                ModuleAtom:'$eval'()
                            end)
                        end)
                    end)
                end)
            end)
        end),
        {ok, list_to_binary(io_lib:format("~tp", [Val]))}
    catch
        Class:Reason:Stacktrace ->
            {error, list_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stacktrace]))}
    end.

%% Evaluate a module with NO default ability handlers. Tooling (transcript
%% recording, replay, capability gates) installs its own frames around the
%% call; the defaults here would shadow them (innermost handler wins), so
%% the bare variant leaves the stack exactly as the caller arranged it.
eval_module_bare(Mod) ->
    ModuleAtom = case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end,
    try
        Val = ModuleAtom:'$eval'(),
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
