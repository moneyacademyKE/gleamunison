-module(gleamunison_health_test).
-export([readiness_fixture/1, http_fixture/2]).

readiness_fixture(Mode) ->
    with_mode(Mode, fun() -> gleamunison@health:readiness() end).

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
        Port = 18103,
        {ServerPid, ServerMonitor} = start_http_server(Port),
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
        ok = wait_for_port(Port, 20),
        {Pid, Monitor}
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

wait_for_port(_Port, 0) -> error(listener_start_timeout);
wait_for_port(Port, Attempts) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 50) of
        {ok, Socket} -> gen_tcp:close(Socket), ok;
        {error, _} -> timer:sleep(20), wait_for_port(Port, Attempts - 1)
    end.