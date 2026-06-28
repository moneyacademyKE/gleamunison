-module(gleamunison_sup).
-behaviour(supervisor).

-export([start_link/0, init/1, start_holder/0, test_supervisor_restart/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

test_supervisor_restart() ->
    Parent = self(),
    spawn(fun() ->
        {ok, SupPid} = start_link(),
        Parent ! {sup_pid, SupPid},
        receive after infinity -> ok end
    end),
    SupPid = receive {sup_pid, P} -> P after 2000 -> error(timeout) end,
    Pid1 = whereis(gleamunison_ets_holder),
    true = is_pid(Pid1),
    exit(Pid1, kill),
    Pid2 = wait_for_restart(Pid1, 100),
    true = is_pid(Pid2),
    true = (Pid1 =/= Pid2),
    exit(SupPid, kill),
    {ok, true}.

wait_for_restart(Pid1, Retries) when Retries > 0 ->
    case whereis(gleamunison_ets_holder) of
        Pid2 when is_pid(Pid2), Pid2 =/= Pid1 -> Pid2;
        _ ->
            timer:sleep(10),
            wait_for_restart(Pid1, Retries - 1)
    end;
wait_for_restart(_, _) ->
    error(restart_timeout).


init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 3, period => 5},
    ChildSpecs = [
        #{
            id => ets_holder,
            start => {?MODULE, start_holder, []},
            restart => permanent,
            shutdown => 2000,
            type => worker,
            modules => [?MODULE]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

start_holder() ->
    Pid = spawn_link(fun() ->
        case whereis(gleamunison_ets_holder) of
            undefined -> register(gleamunison_ets_holder, self());
            _ -> ok
        end,
        try ets:new(gleamunison_store_sup, [set, public, named_table]) catch _:_ -> ok end,
        try ets:new(gleamunison_peer_refs, [set, public, named_table]) catch _:_ -> ok end,
        receive after infinity -> ok end
    end),
    {ok, Pid}.

