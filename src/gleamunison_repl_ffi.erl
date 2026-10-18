-module(gleamunison_repl_ffi).
-export([eval_module/1, eval_module_bare/1, read_line/1]).

eval_module(Mod) ->
    run_with_timeout(fun() -> eval_module_inner(Mod) end).

eval_module_inner(Mod) ->
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
    run_with_timeout(fun() -> eval_module_bare_inner(Mod) end).

eval_module_bare_inner(Mod) ->
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

run_with_timeout(Fun) when is_function(Fun, 0) ->
    Parent = self(),
    Ref = make_ref(),
    InitialState = copyable_process_dictionary(),
    {Pid, Mon} = spawn_monitor(fun() ->
        Result = run_in_worker(InitialState, Fun),
        Parent ! {Ref, Result, copyable_process_dictionary()}
    end),
    Timeout = evaluation_timeout_ms(),
    receive
        {Ref, {ok, Result}, UpdatedState} ->
            erlang:demonitor(Mon, [flush]),
            restore_process_dictionary(UpdatedState),
            Result;
        {Ref, {raised, Class, Reason}, UpdatedState} ->
            erlang:demonitor(Mon, [flush]),
            restore_process_dictionary(UpdatedState),
            {error, list_to_binary(io_lib:format("~p:~p", [Class, Reason]))};
        {'DOWN', Mon, process, Pid, Reason} ->
            {error, list_to_binary(io_lib:format("evaluation_worker_down: ~p", [Reason]))}
    after Timeout ->
        exit(Pid, kill),
        receive {'DOWN', Mon, process, Pid, _} -> ok after 1000 -> ok end,
        {error, <<"evaluation_timeout">>}
    end.

run_in_worker(State, Fun) ->
    restore_process_dictionary(State),
    try Fun() of
        Value -> {ok, Value}
    catch
        Class:Reason -> {raised, Class, Reason}
    end.

copyable_process_dictionary() ->
    [Entry || Entry = {Key, _Value} <- erlang:get(), copyable_key(Key)].

copyable_key({gleamunison_handlers}) -> true;
copyable_key(gleamunison_transcript_log) -> true;
copyable_key(gleamunison_transcript_playback) -> true;
copyable_key({state_val, _Key}) -> true;
copyable_key({pd_counter, _Key}) -> true;
copyable_key({pd_records, _Key}) -> true;
copyable_key(Key) when is_binary(Key) -> true;
copyable_key(_) -> false.

restore_process_dictionary(Entries) ->
    lists:foreach(fun({Key, Value}) -> erlang:put(Key, Value) end, Entries).

evaluation_timeout_ms() ->
    case os:getenv("GLEAMUNISON_EVAL_TIMEOUT_MS") of
        false -> 30000;
        "" -> 30000;
        Value ->
            try
                Parsed = list_to_integer(Value),
                if
                    Parsed < 1 -> 30000;
                    Parsed > 300000 -> 300000;
                    true -> Parsed
                end
            catch
                _:_ -> 30000
            end
    end.

read_line(_Prompt) ->
    case io:get_line('') of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line when is_list(Line) -> {ok, unicode:characters_to_binary(Line)};
        Line when is_binary(Line) -> {ok, Line}
    end.
