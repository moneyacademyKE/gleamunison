-module(gleamunison_health_test).
-export([readiness_fixture/1, http_fixture/2]).

readiness_fixture(Mode) ->
    with_mode(Mode, fun() -> gleamunison_readiness:ready() end).

with_mode(Mode, Fun) ->
    Old = persistent_term:get({gleamunison, active_storage}, undefined),
    Names = ["GLEAMUNISON_MAX_MEMORY_MB", "GLEAMUNISON_REQUIRED_SERVICES"],
    Envs = [{Name, os:getenv(Name)} || Name <- Names],
    [os:unsetenv(Name) || Name <- Names],
    {module, m_0000000a} = code:ensure_loaded(m_0000000a),
    Cleanup = setup_mode(Mode),
    try Fun()
    after
        Cleanup(),
        case Old of
            undefined -> persistent_term:erase({gleamunison, active_storage});
            _ -> persistent_term:put({gleamunison, active_storage}, Old)
        end,
        [case Value of
            false -> os:unsetenv(Name);
            _ -> os:putenv(Name, Value)
        end || {Name, Value} <- Envs]
    end.

setup_mode(0) ->
    persistent_term:erase({gleamunison, active_storage}),
    fun() -> ok end;
setup_mode(2) ->
    Path = gleamunison_cas_test:scratch_path(),
    {ok, Table} = gleamunison_storage:dets_new(Path),
    {ok, nil} = gleamunison_storage:dets_close(Table),
    fun() -> {ok, nil} = gleamunison_storage:dets_delete_file(Path) end;
setup_mode(7) ->
    Services = start_real_services(),
    true = os:putenv("GLEAMUNISON_REQUIRED_SERVICES", "http,mcp,sync"),
    Services;
setup_mode(8) ->
    Cleanup = start_real_services(),
    Pid = whereis(gleamunison_mcp_session),
    true = erlang:suspend_process(Pid),
    true = os:putenv("GLEAMUNISON_REQUIRED_SERVICES", "mcp"),
    fun() -> true = erlang:resume_process(Pid), Cleanup() end;
setup_mode(Mode) ->
    _Table = gleamunison_storage:new(),
    case Mode of
        3 -> os:putenv("GLEAMUNISON_MAX_MEMORY_MB", "1");
        4 -> os:putenv("GLEAMUNISON_MAX_MEMORY_MB", "not-an-integer");
        5 -> os:putenv("GLEAMUNISON_REQUIRED_SERVICES", "http,mcp,sync");
        6 -> os:putenv("GLEAMUNISON_REQUIRED_SERVICES", "telepathy");
        _ -> ok
    end,
    fun() -> ok end.

start_real_services() ->
    {ok, nil} = gleamunison_mcp_session:start([]),
    SyncStarted = case whereis(gleamunison_tcp_sync) of
        undefined -> {ok, _} = gleamunison_tcp_sync:start_link(), true;
        _ -> false
    end,
    fun() ->
        Pid = whereis(gleamunison_mcp_session),
        Monitor = erlang:monitor(process, Pid),
        nil = gleamunison_mcp_session:stop(),
        receive {'DOWN', Monitor, process, Pid, _} -> ok after 1000 -> error(mcp_cleanup_timeout) end,
        case SyncStarted of true -> ok = gleamunison_tcp_sync:stop(); false -> ok end
    end.

http_fixture(Mode, Path) ->
    with_mode(Mode, fun() ->
        %% A kernel-assigned free port, so this fixture cannot collide with
        %% another test's server. It used to hardcode the very port that
        %% mcp_http_test also binds inside the same node: whichever came second
        %% either failed to bind or, worse, quietly talked to the other test's
        %% listener and passed for the wrong reason. Port 0 is not an option
        %% here — gleamunison_http_sup:init/1 reads Port =< 0 as "run no
        %% listener at all".
        {ServerPid, ServerMonitor, Port} = start_http_server(free_port()),
        try
            {ok, _} = application:ensure_all_started(inets),
            Url = "http://127.0.0.1:" ++ integer_to_list(Port) ++ binary_to_list(Path),
            case httpc:request(get, {Url, []}, [{timeout, 2000}, {connect_timeout, 1000}],
                               [{body_format, binary}]) of
                {ok, {{_, Status, _}, _Headers, Body}} -> {ok, {Status, Body}};
                {error, Reason} -> {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
            end
        after
            ok = gleamunison_http:stop_server(),
            wait_for_server_exit(ServerPid, ServerMonitor)
        end
    end).

start_http_server(Port) ->
    {Pid, Monitor} = spawn_monitor(fun() ->
        ok = gleamunison_http:start_server(Port)
    end),
    try
        ok = wait_for_listening(Port, 200),
        {Pid, Monitor, Port}
    catch
        error:Reason ->
            exit(Pid, kill),
            receive {'DOWN', Monitor, process, Pid, _} -> ok after 1000 -> ok end,
            error(Reason)
    end.

wait_for_server_exit(Pid, Monitor) ->
    receive
        {'DOWN', Monitor, process, Pid, _Reason} -> ok
    after 1000 ->
        error(http_stop_timeout)
    end.

%% A kernel-assigned free port, bound on the same loopback address the server
%% uses by default. The probe socket is closed before the server starts, so
%% there is a small window in which another process could take the port; that
%% window now fails loudly below, where the old hardcoded port could instead
%% succeed against somebody else's listener.
free_port() ->
    {ok, Socket} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true},
                                      {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(Socket),
    ok = gen_tcp:close(Socket),
    Port.

%% gleamunison_http:listen/2 registers {Owner, ListenSocket} in a
%% persistent_term only after gen_tcp:listen succeeded, so that registration is
%% the readiness signal. The old code connected to a hardcoded port in a loop
%% instead (20 attempts, ~1.4s), which raced the listener and could not tell
%% our server from another test's. Matching the port we asked for means a
%% leftover listener can no longer masquerade as ours.
wait_for_listening(Port, Attempts) ->
    case registered_port() of
        {ok, Port} -> ok;
        _ when Attempts =< 0 -> error(listener_start_timeout);
        _ ->
            timer:sleep(10),
            wait_for_listening(Port, Attempts - 1)
    end.

%% The registered listener's port, or undefined when nothing is registered yet
%% or the registration is stale because its socket is already closed.
registered_port() ->
    case persistent_term:get({gleamunison_http, listener}, undefined) of
        {_Owner, Socket} ->
            case inet:port(Socket) of
                {ok, Port} -> {ok, Port};
                {error, _} -> undefined
            end;
        undefined -> undefined
    end.
