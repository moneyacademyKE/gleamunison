-module(gleamunison_http).
-export([start_server/1, stop_server/0]).

start_server(Port) when is_integer(Port) ->
    case ets:whereis(gleamunison_http_counter) of
        undefined ->
            ets:new(gleamunison_http_counter, [set, public, named_table]),
            ets:insert(gleamunison_http_counter, {count, 0});
        _ ->
            ok
    end,
    spawn(fun() -> server_loop(Port) end),
    io:format("Gleamunison webserver listening on http://localhost:~p~n", [Port]),
    server_control_loop(Port).

server_control_loop(Port) ->
    receive
        stop -> ok;
        _ -> server_control_loop(Port)
    end.

stop_server() ->
    case erlang:whereis(gleamunison_http_server) of
        undefined -> ok;
        Pid -> exit(Pid, shutdown)
    end.

server_loop(Port) ->
    register(gleamunison_http_server, self()),
    {ok, ListenSocket} = gen_tcp:listen(Port, [
        binary, {active, false}, {reuseaddr, true},
        {packet, http_bin}, {backlog, 100}, {ip, {127, 0, 0, 1}}
    ]),
    accept_loop(ListenSocket).

accept_loop(ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} ->
            spawn(fun() -> handle_request(Socket) end),
            accept_loop(ListenSocket);
        {error, closed} ->
            ok;
        {error, Reason} ->
            io:format("Accept error: ~p~n", [Reason]),
            accept_loop(ListenSocket)
    end.

handle_request(Socket) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, {http_request, 'GET', {abs_path, Path}, _Version}} ->
            handle_route(Socket, Path);
        {ok, _Other} ->
            gleamunison_http_util:send_response(Socket, 501, <<"Not Implemented">>);
        {error, closed} ->
            ok;
        {error, timeout} ->
            gen_tcp:close(Socket)
    end.

handle_route(Socket, <<"/eval", Rest/binary>>) ->
    gleamunison_http_routes:handle_eval_route(Socket, Rest);
handle_route(Socket, <<"/counter">>) ->
    gleamunison_http_routes:handle_counter_route(Socket);
handle_route(Socket, <<"/define", Rest/binary>>) ->
    gleamunison_http_routes:handle_define_route(Socket, Rest);
handle_route(Socket, <<"/browse">>) ->
    gleamunison_http_routes:handle_browse_route(Socket);
handle_route(Socket, <<"/api/status">>) ->
    gleamunison_http_routes:handle_status_route(Socket);
handle_route(Socket, <<"/api/events">>) ->
    gleamunison_http_routes:handle_sse_route(Socket);
handle_route(Socket, <<"/api/processes">>) ->
    gleamunison_http_routes:handle_processes_route(Socket);
handle_route(Socket, <<"/api/sync-status">>) ->
    gleamunison_http_routes:handle_sync_status_route(Socket);
handle_route(Socket, <<"/api/redefinitions", _Rest/binary>>) ->
    gleamunison_http_routes:handle_redefinitions_route(Socket);
handle_route(Socket, <<"/api/logs">>) ->
    gleamunison_http_routes:handle_logs_route(Socket);
handle_route(Socket, <<"/api/modules">>) ->
    gleamunison_http_routes:handle_enhanced_modules_route(Socket);
handle_route(Socket, <<"/api/traces">>) ->
    gleamunison_http_routes:handle_traces_route(Socket);
handle_route(Socket, <<"/api/traces/", Id/binary>>) ->
    gleamunison_http_routes:handle_trace_detail_route(Socket, Id);
handle_route(Socket, <<"/api/health">>) ->
    handle_health_route(Socket);
handle_route(Socket, Path) ->
    gleamunison_http_routes:serve_static(Socket, Path).

handle_health_route(Socket) ->
    {_Node, ModCount, _MemMB} = gleamunison_health:node_status(),
    Status = case ModCount > 0 of
        true -> <<"healthy">>;
        false -> <<"unhealthy">>
    end,
    Json = iolist_to_binary(io_lib:format(
        "{\"status\":\"~s\",\"loaded_modules\":~p}",
        [Status, ModCount])),
    gleamunison_http_util:send_json(Socket, 200, Json).

