-module(gleamunison_http).
-export([start_server/1, stop_server/0]).

-define(MAX_BODY_BYTES, 1048576).
-define(MAX_HEADER_COUNT, 64).
-define(MAX_HEADER_BYTES, 16384).

start_server(Port) when is_integer(Port) ->
    application:ensure_all_started(crypto),
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
            handle_get_headers(Socket, Path);
        {ok, {http_request, 'POST', {abs_path, Path}, _Version}} ->
            handle_post_headers(Socket, Path);
        {ok, _Other} ->
            gleamunison_http_util:send_response(Socket, 501, <<"Not Implemented">>);
        {error, closed} ->
            ok;
        {error, timeout} ->
            gen_tcp:close(Socket)
    end.

handle_get_headers(Socket, Path) ->
    case read_headers(Socket, 0, [], 0) of
        {ok, _ContentLength, Headers} ->
            case authorized(Path, Headers) of
                true -> handle_route(Socket, Path);
                false -> send_unauthorized(Socket)
            end;
        {error, headers_too_large} -> send_error(Socket, 413, <<"headers too large">>);
        {error, _} -> send_error(Socket, 400, <<"invalid headers">>)
    end.

handle_post_headers(Socket, Path) ->
    case read_headers(Socket, 0, [], 0) of
        {ok, ContentLength, Headers} ->
            case authorized(Path, Headers) of
                false -> send_unauthorized(Socket);
                true -> handle_post_body(Socket, Path, ContentLength)
            end;
        {error, body_too_large} -> send_error(Socket, 413, <<"request body too large">>);
        {error, headers_too_large} -> send_error(Socket, 413, <<"headers too large">>);
        {error, _} -> send_error(Socket, 400, <<"invalid headers">>)
    end.

handle_post_body(Socket, Path, ContentLength) ->
    inet:setopts(Socket, [{packet, raw}]),
    case recv_body(Socket, ContentLength, <<>>) of
        {ok, Body} -> handle_post_route(Socket, Path, Body);
        {error, _} -> send_error(Socket, 400, <<"incomplete request body">>)
    end.

%% Read headers until end-of-headers. Header names are normalized so auth and
%% content-length checks do not depend on OTP's packet representation.
read_headers(Socket, ContentLength, Headers, HeaderBytes) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, {http_header, _, Name, _, Value}} ->
            HeaderName = header_binary(Name),
            HeaderValue = header_binary(Value),
            NewBytes = HeaderBytes + byte_size(HeaderName) + byte_size(HeaderValue),
            case {length(Headers) < ?MAX_HEADER_COUNT, NewBytes =< ?MAX_HEADER_BYTES} of
                {false, _} -> {error, headers_too_large};
                {_, false} -> {error, headers_too_large};
                {true, true} ->
                    case normalize_header_name(HeaderName) of
                        <<"content-length">> ->
                            case parse_content_length(HeaderValue) of
                                {ok, Length} when Length >= 0, Length =< ?MAX_BODY_BYTES ->
                                    read_headers(Socket, Length, [{<<"content-length">>, HeaderValue} | Headers], NewBytes);
                                {ok, _} -> {error, body_too_large};
                                error -> {error, invalid_content_length}
                            end;
                        Normalized ->
                            read_headers(Socket, ContentLength, [{Normalized, HeaderValue} | Headers], NewBytes)
                    end
            end;
        {ok, http_eoh} ->
            {ok, ContentLength, Headers};
        {error, Reason} ->
            {error, Reason}
    end.

recv_body(_Socket, 0, Acc) -> {ok, Acc};
recv_body(Socket, Remaining, Acc) ->
    case gen_tcp:recv(Socket, Remaining, 5000) of
        {ok, Chunk} ->
            Size = byte_size(Chunk),
            recv_body(Socket, Remaining - Size, <<Acc/binary, Chunk/binary>>);
        {error, Reason} -> {error, Reason}
    end.

header_binary(Value) when is_binary(Value) -> Value;
header_binary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
header_binary(Value) when is_list(Value) -> list_to_binary(Value).

normalize_header_name(Name) ->
    list_to_binary(string:lowercase(binary_to_list(Name))).

parse_content_length(Value) ->
    try
        {ok, binary_to_integer(list_to_binary(string:trim(binary_to_list(Value))))}
    catch
        _:_ -> error
    end.

authorized(Path, Headers) ->
    case os:getenv("GLEAMUNISON_HTTP_TOKEN") of
        false -> true;
        "" -> true;
        Expected ->
            case protected_path(Path) of
                false -> true;
                true ->
                    ExpectedBin = list_to_binary(Expected),
                    Provided = case lists:keyfind(<<"authorization">>, 1, Headers) of
                        {_, Value} -> Value;
                        false -> <<>>
                    end,
                    case Provided of
                        <<"Bearer ", Token/binary>> -> constant_time_equal(ExpectedBin, Token);
                        _ -> false
                    end
            end
    end.

protected_path(<<"/eval", _/binary>>) -> true;
protected_path(<<"/define", _/binary>>) -> true;
protected_path(<<"/mcp">>) -> true;
protected_path(_) -> false.

constant_time_equal(Expected, Provided) when is_binary(Expected), is_binary(Provided) ->
    constant_time_hash_compare(crypto:hash(sha256, Expected), crypto:hash(sha256, Provided), 0).

constant_time_hash_compare(<<A, RestA/binary>>, <<B, RestB/binary>>, Acc) ->
    constant_time_hash_compare(RestA, RestB, Acc bor (A bxor B));
constant_time_hash_compare(<<>>, <<>>, Acc) -> Acc =:= 0.

send_unauthorized(Socket) ->
    gleamunison_http_util:send_json(Socket, 401, <<"{\"error\":\"unauthorized\"}">>).

send_error(Socket, Status, Message) ->
    Json = iolist_to_binary(io_lib:format("{\"error\":~ts}", [gleamunison_http_util:escape_json(Message)])),
    gleamunison_http_util:send_json(Socket, Status, Json).

handle_post_route(Socket, <<"/mcp">>, Body) ->
    handle_mcp_route(Socket, Body);
handle_post_route(Socket, _Path, _Body) ->
    gleamunison_http_util:send_json(Socket, 404, <<"{\"error\":\"not found\"}">>).

handle_mcp_route(Socket, Body) ->
    case whereis(gleamunison_mcp_session) of
        undefined ->
            gleamunison_http_util:send_json(
                Socket, 503, <<"{\"error\":\"mcp session not running\"}">>);
        Pid ->
            Pid ! {rpc, Body, self()},
            receive
                {mcp_reply, {ok, Reply}} ->
                    gleamunison_http_util:send_json(Socket, 200, Reply);
                {mcp_reply, no_reply} ->
                    gleamunison_http_util:send_json(Socket, 202, <<>>)
            after 30000 ->
                gleamunison_http_util:send_json(
                    Socket, 504, <<"{\"error\":\"mcp session timeout\"}">>)
            end
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
