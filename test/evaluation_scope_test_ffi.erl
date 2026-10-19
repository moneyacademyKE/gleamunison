-module(evaluation_scope_test_ffi).
-export(['$eval'/0, descendants_die/0, cancelled_owner/0, successful_scope/0]).

successful_scope() ->
    Parent = self(),
    {ok, done} = gleamunison_eval_scope:run(fun() ->
        Child = spawn(fun() -> receive after infinity -> ok end end),
        Parent ! {success_child, Child},
        done
    end, 1000),
    receive {success_child, Child} -> not is_process_alive(Child)
    after 1000 -> false end.

cancelled_owner() ->
    Parent = self(),
    {Owner, OwnerMon} = spawn_monitor(fun() ->
        gleamunison_eval_scope:run(fun() ->
            Child = spawn(fun() -> receive after infinity -> ok end end),
            Parent ! {cancel_child, Child},
            receive after infinity -> ok end
        end, 1000)
    end),
    receive {cancel_child, Child} ->
        ChildMon = monitor(process, Child),
        exit(Owner, kill),
        receive {'DOWN', OwnerMon, process, Owner, _} -> ok after 1000 -> error(owner_survived) end,
        receive {'DOWN', ChildMon, process, Child, _} -> true
        after 1000 -> exit(Child, kill), false end
    after 1000 -> exit(Owner, kill), false end.

'$eval'() ->
    Parent = get(<<"scope_probe_parent">>),
    spawn(fun() ->
        process_flag(trap_exit, true),
        Grandchild = spawn(fun() -> receive after infinity -> ok end end),
        Parent ! {descendants, self(), Grandchild},
        receive after infinity -> ok end
    end),
    receive after infinity -> ok end.

descendants_die() ->
    Old = os:getenv("GLEAMUNISON_EVAL_TIMEOUT_MS"),
    os:putenv("GLEAMUNISON_EVAL_TIMEOUT_MS", "50"),
    put(<<"scope_probe_parent">>, self()),
    try
        {error, <<"evaluation_timeout">>} = gleamunison_repl_ffi:eval_module_bare(?MODULE),
        receive
            {descendants, Child, Grandchild} ->
                ChildAlive = is_process_alive(Child),
                GrandchildAlive = is_process_alive(Grandchild),
                io:format("child_alive_after_timeout=~p grandchild_alive_after_timeout=~p~n", [ChildAlive, GrandchildAlive]),
                %% Red runs must not themselves leave processes behind.
                exit(Child, kill), exit(Grandchild, kill),
                not ChildAlive andalso not GrandchildAlive
        after 1000 -> error(no_descendant_probe)
        end
    after
        erase(<<"scope_probe_parent">>),
        case Old of false -> os:unsetenv("GLEAMUNISON_EVAL_TIMEOUT_MS"); _ -> os:putenv("GLEAMUNISON_EVAL_TIMEOUT_MS", Old) end
    end.
