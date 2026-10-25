-module(gleamunison_repl_ffi).
-export([eval_module/1, eval_module_bare/1, call_eval/2, read_line/1]).

eval_module(Mod) ->
    run_with_timeout(fun() -> eval_module_inner(Mod) end).
eval_module_inner(Mod) ->
    ModuleAtom = module_atom(Mod),
    try
        Val = with_baseline_handlers(fun() -> ModuleAtom:'$eval'() end),
        {ok, gleamunison_render:term(Val)}
    catch
        Class:Reason:Stacktrace ->
            {error, describe_error(Class, Reason, Stacktrace)}
    end.

%% The ability frames a top-level evaluation runs under. This is one table, not
%% six nested calls, because the REPL and `run` are two doors into the same
%% evaluator: a stored definition that performs `Console print` must print
%% through either door. Two owners of this policy meant `publish` could admit an
%% effectful definition on an `io` attestation and `run` would then die with
%% `{unhandled_ability,m_74eafa15,0}` — admitted, then unrunnable.
%%
%% The error path reads the same table (`baseline_names/0`), so an ability can
%% never be handled in one projection and unnamed in the other.
baseline_abilities() ->
    [
        {<<"m_74eafa15">>, <<"Console">>, #{
            0 => fun([Arg], Cont) ->
                print_text(Arg),
                Cont(0)
            end
        }},
        {<<"m_fe60582e">>, <<"State">>, #{
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
        {<<"m_b514a6e3">>, <<"Math">>, #{
            0 => fun([X, Y], Cont) -> Cont(X + Y) end,
            1 => fun([X, Y], Cont) -> Cont(X - Y) end,
            2 => fun([X, Y], Cont) -> Cont(X * Y) end
        }},
        {<<"m_d17eaeb6">>, <<"Show">>, #{
            0 => fun([Val], Cont) ->
                Str = case is_binary(Val) of
                    true -> << "\"", Val/binary, "\"" >>;
                    false -> gleamunison_render:term(Val)
                end,
                Cont(Str)
            end
        }},
        {<<"m_ffa98e02">>, <<"Remote">>, #{
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
        {<<"m_a12979b5">>, <<"LLM">>, #{
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
        }}
    ].

%% Fold the table into a handler stack around Fun. foldr keeps Console
%% outermost, which is the nesting this module shipped before the table existed.
with_baseline_handlers(Fun) ->
    Stacked =
        lists:foldr(
            fun({Key, _Name, Ops}, Inner) ->
                fun() -> gleamunison_effets:handle_comp({Key, Ops}, Inner) end
            end,
            Fun,
            baseline_abilities()
        ),
    Stacked().

baseline_names() ->
    maps:from_list([{Key, Name} || {Key, Name, _Ops} <- baseline_abilities()]).

%% `~s` renders a binary byte-by-byte, so any non-ASCII text came out as
%% mojibake ("hÃ©llo"). Print UTF-8 as text, and fall back to the term form for
%% a binary that is not valid UTF-8 rather than crashing the evaluation.
print_text(Arg) when is_binary(Arg) ->
    case unicode:characters_to_list(Arg, utf8) of
        List when is_list(List) -> io:format("~ts~n", [List]);
        _ -> io:format("~p~n", [Arg])
    end;
print_text(Arg) ->
    io:format("~p~n", [Arg]).

provided_ability_list() ->
    lists:join(", ", [Name || {_Key, Name, _Ops} <- baseline_abilities()]).

%% An unhandled ability reaches the user as `{unhandled_ability,m_74eafa15,0}`:
%% a module hash and an operation index, which name nothing a person can act on.
%% Translate it into the ability's name and the set this evaluator provides.
describe_error(error, {unhandled_ability, Ability, Op}, _Stacktrace) ->
    case maps:find(Ability, baseline_names()) of
        {ok, Name} ->
            %% In the baseline, yet unhandled: a caller installed a frame that
            %% shadowed or removed it (capability gates do exactly this).
            iolist_to_binary(io_lib:format(
                "ability ~s operation ~p has no handler on this stack; "
                "a capability frame removed or shadowed the default",
                [Name, Op]
            ));
        error ->
            iolist_to_binary(io_lib:format(
                "ability ~s (operation ~p) is not handled here; "
                "a top-level evaluation provides ~s only",
                [Ability, Op, provided_ability_list()]
            ))
    end;
describe_error(Class, Reason, Stacktrace) ->
    list_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stacktrace])).

%% Evaluate a module with NO default ability handlers. Tooling (transcript
%% recording, replay, capability gates) installs its own frames around the
%% call; the defaults here would shadow them (innermost handler wins), so
%% the bare variant leaves the stack exactly as the caller arranged it.
eval_module_bare(Mod) ->
    run_with_timeout(fun() -> eval_module_bare_inner(Mod) end).

%% Call a compiled definition with arguments. The compiler emits exactly
%% '$eval'/0 (a function is a VALUE: arity-N is a curried fun), so application
%% is one erlang:apply/2 per argument. Same timeout protection as
%% eval_module_bare; the raw term goes back so the caller picks the rendering
%% (text now, --json next). Args arrive as Erlang terms (see parse_term_arg).
%%
%% The baseline frames go on here too. `run` executes stored content that the
%% same turnstile admitted, so it must be able to execute what it admitted;
%% installing fewer handlers than the REPL made an effectful definition
%% publishable and unrunnable.
call_eval(Mod, Args) ->
    run_with_timeout(fun() -> call_eval_inner(Mod, Args) end).

call_eval_inner(Mod, Args) ->
    ModuleAtom = module_atom(Mod),
    try
        V0 = with_baseline_handlers(fun() -> ModuleAtom:'$eval'() end),
        Val = lists:foldl(fun(A, F) -> erlang:apply(F, [A]) end, V0, Args),
        {ok, Val}
    catch
        Class:Reason:Stacktrace ->
            {error, describe_error(Class, Reason, Stacktrace)}
    end.

eval_module_bare_inner(Mod) ->
    ModuleAtom = module_atom(Mod),
    try
        Val = ModuleAtom:'$eval'(),
        {ok, gleamunison_render:term(Val)}
    catch
        Class:Reason:Stacktrace ->
            {error, list_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stacktrace]))}
    end.

module_atom(Mod) ->
    case is_binary(Mod) of
        true -> erlang:binary_to_atom(Mod, utf8);
        false -> Mod
    end.

run_with_timeout(Fun) when is_function(Fun, 0) ->
    InitialState = copyable_process_dictionary(),
    Work = fun() ->
        Result = run_in_worker(InitialState, Fun),
        {Result, copyable_process_dictionary()}
    end,
    case gleamunison_eval_scope:run(Work, evaluation_timeout_ms()) of
        {ok, {{ok, Result}, UpdatedState}} ->
            restore_process_dictionary(UpdatedState),
            Result;
        {ok, {{raised, Class, Reason}, UpdatedState}} ->
            restore_process_dictionary(UpdatedState),
            {error, list_to_binary(io_lib:format("~p:~p", [Class, Reason]))};
        {error, _} = Error -> Error
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