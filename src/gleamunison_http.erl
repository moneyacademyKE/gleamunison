-module(gleamunison_http).
-behaviour(gen_server).
-export([start_link/1, start_server/1, stop_server/0, drain/1, init/1, handle_call/3,
         handle_cast/2, handle_info/2, terminate/2, worker_count/1]).

-define(MAX_BODY_BYTES, 1048576).
-define(MAX_HEADER_COUNT, 64).
-define(MAX_HEADER_BYTES, 16384).
-define(MAX_WORKERS, 64).

start_link(Port) when is_integer(Port) ->
    gen_server:start_link(?MODULE, Port, []).

start_server(Port) when is_integer(Port) ->
    case gleamunison_runtime_sup:start_http(Port) of
        {ok, Pid} -> wait_for_server(Pid), ok;
        {error, {already_started, Pid}} -> wait_for_server(Pid), ok;
        {error, Reason} -> {error, Reason}
    end.

wait_for_server(Pid) when is_pid(Pid) ->
    Ref = erlang:monitor(process, Pid),
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> ok
    end.

stop_server() ->
    gleamunison_runtime_sup:stop_http().

%% Graceful drain: stop accepting new connections, then wait for in-flight
%% workers to finish up to Timeout ms. Returns drained | {timeout, Remaining}.
%% The server process stays alive afterwards; stop_server/0 finishes the job.
drain(Timeout) when is_integer(Timeout), Timeout >= 0 ->
    case persistent_term:get({gleamunison_http, listener}, undefined) of
        {Pid, _Socket} when is_pid(Pid) ->
            gen_server:call(Pid, {drain, Timeout}, Timeout + 1000);
        _ -> {error, <<"http_not_running">>}
    end.

init(Port) ->
    application:ensure_all_started(crypto),
    ensure_counter(),
    case bind_gate() of
        {ok, BindIp} -> listen(Port, BindIp);
        {error, _} = Refusal -> {stop, Refusal}
    end.

%% Loopback is the default and needs no contract. Any other bind address
%% requires the authenticated-remote profile plus an auth contract; the
%% decision lives in gleamunison@auth:bind_decision/1 (one policy owner).
bind_gate() ->
    Address = case os:getenv("GLEAMUNISON_BIND_ADDRESS") of
        false -> <<"127.0.0.1">>;
        "" -> <<"127.0.0.1">>;
        Value -> list_to_binary(Value)
    end,
    Profile = case os:getenv("GLEAMUNISON_PROFILE") of
        false -> <<"local">>;
        P -> list_to_binary(P)
    end,
    Input = {bind_input, Address, Profile, http_token_present(), sync_token_present()},
    case gleamunison@auth:bind_decision(Input) of
        allow -> parse_bind_ip(Address);
        {refuse, Reason} -> {error, Reason}
    end.

http_token_present() ->
    case os:getenv("GLEAMUNISON_HTTP_TOKEN") of
        false -> false;
        "" -> false;
        _ -> true
    end.

sync_token_present() ->
    case os:getenv("GLEAMUNISON_SYNC_TOKEN") of
        false -> false;
        "" -> false;
        _ -> true
    end.

parse_bind_ip(<<"127.0.0.1">>) -> {ok, {127, 0, 0, 1}};
parse_bind_ip(<<"0.0.0.0">>) -> {ok, {0, 0, 0, 0}};
parse_bind_ip(<<"::1">>) -> {ok, {0, 0, 0, 0, 0, 0, 0, 1}};
parse_bind_ip(Other) ->
    case inet:parse_address(binary_to_list(Other)) of
        {ok, Ip} -> {ok, Ip};
        {error, _} -> {error, <<"invalid_bind_address">>}
    end.

listen(Port, BindIp) ->
    case gen_tcp:listen(Port, [binary, {active, false}, {reuseaddr, true},
                               {packet, http_bin}, {backlog, 100},
                               {ip, BindIp}]) of
        {ok, ListenSocket} ->
            Owner = self(),
            Acceptor = spawn_link(fun() -> accept_loop(Owner, ListenSocket) end),
            persistent_term:put({gleamunison_http, listener}, {self(), ListenSocket}),
            {ok, #{socket => ListenSocket, acceptor => Acceptor, workers => #{}}};
        {error, Reason} -> {stop, Reason}
    end.

ensure_counter() ->
    case ets:whereis(gleamunison_http_counter) of
        undefined ->
            ets:new(gleamunison_http_counter, [set, public, named_table]),
            ets:insert(gleamunison_http_counter, {count, 0});
        _ -> ok
    end.

worker_count(Pid) when is_pid(Pid) ->
    case sys:get_state(Pid) of
        #{workers := Workers} -> map_size(Workers)
    end.

handle_call(stop, _From, State) -> {stop, normal, ok, State};
handle_call({drain, Timeout}, _From, #{socket := Socket, acceptor := Acceptor, workers := Workers} = State) ->
    %% Close the listener and stop the acceptor first: no new work arrives
    %% while we wait. Unlink BEFORE the shutdown: the acceptor is linked to
    %% this server, so the shutdown reason backfires through the link and
    %% kills the server before it replies whenever the acceptor has not yet
    %% noticed the closed socket — the race CI caught on macos-28 (PR #30):
    %% the drain caller crashed with {shutdown, {gen_server, call, ...}}.
    %% unlink/1 also discards an exit signal already in flight.
    %% Worker DOWNs are consumed here so the wait observes real progress
    %% instead of a frozen map.
    unlink(Acceptor),
    catch gen_tcp:close(Socket),
    exit(Acceptor, shutdown),
    persistent_term:erase({gleamunison_http, listener}),
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    Result = wait_drained(Workers, Deadline),
    {reply, Result, State};
handle_call(_Request, _From, State) -> {reply, {error, unsupported}, State}.
handle_cast(_, State) -> {noreply, State}.

handle_info({accepted, Socket}, #{workers := Workers} = State) ->
    case map_size(Workers) < ?MAX_WORKERS of
        true ->
            {Pid, Mon} = spawn_monitor(fun() -> handle_request(Socket) end),
            {noreply, State#{workers := Workers#{Pid => Mon}}};
        false ->
            gleamunison_http_util:send_response(Socket, 503, <<"busy">>),
            gen_tcp:close(Socket),
            {noreply, State}
    end;
handle_info({'DOWN', Mon, process, Pid, _Reason}, #{workers := Workers} = State) ->
    case maps:find(Pid, Workers) of
        {ok, Mon} -> {noreply, State#{workers := maps:remove(Pid, Workers)}};
        error -> {noreply, State}
    end;
handle_info(_, State) -> {noreply, State}.

terminate(_, #{socket := Socket, acceptor := Acceptor, workers := Workers}) ->
    %% Same unlink as in drain: the acceptor's shutdown must not backfire
    %% through the link and rewrite the reason this server terminates with.
    unlink(Acceptor),
    catch gen_tcp:close(Socket),
    exit(Acceptor, shutdown),
    maps:foreach(fun(Pid, _) -> exit(Pid, shutdown) end, Workers),
    persistent_term:erase({gleamunison_http, listener}),
    ok.

wait_drained(Workers, Deadline) ->
    case map_size(Workers) of
        0 -> drained;
        N ->
            Remaining = Deadline - erlang:monotonic_time(millisecond),
            if Remaining =< 0 -> {timeout, N};
               true ->
                   receive
                       {'DOWN', _Mon, process, Pid, _} ->
                           wait_drained(maps:remove(Pid, Workers), Deadline)
                   after 25 ->
                       wait_drained(Workers, Deadline)
                   end
            end
    end.

accept_loop(Owner, ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} -> Owner ! {accepted, Socket}, accept_loop(Owner, ListenSocket);
        {error, closed} -> ok;
        {error, _Reason} -> timer:sleep(25), accept_loop(Owner, ListenSocket)
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

%% Public: the UI shell/assets and bounded operational probes. Every data
%% and mutation route (including unknown future routes) requires the token.
protected_path(<<"/">>) -> false;
protected_path(<<"/index.html">>) -> false;
protected_path(<<"/static/", _/binary>>) -> false;
protected_path(<<"/api/live">>) -> false;
protected_path(<<"/api/ready">>) -> false;
protected_path(<<"/api/health">>) -> false;
protected_path(_) -> true.

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
        _Pid ->
            case catch gen_server:call(gleamunison_mcp_session, {rpc, Body}, 30000) of
                {ok, {respond, Reply}} ->
                    gleamunison_http_util:send_json(Socket, 200, Reply);
                {ok, no_reply} ->
                    gleamunison_http_util:send_json(Socket, 202, <<>>);
                {error, busy} ->
                    gleamunison_http_util:send_json(Socket, 503, <<"{\"error\":\"mcp session busy\"}">>);
                {'EXIT', _} ->
                    gleamunison_http_util:send_json(Socket, 503, <<"{\"error\":\"mcp session unavailable\"}">>);
                _ ->
                    gleamunison_http_util:send_json(Socket, 504, <<"{\"error\":\"mcp session timeout\"}">>)
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
handle_route(Socket, <<"/api/observability">>) ->
    gleamunison_http_routes:handle_observability_route(Socket);
handle_route(Socket, <<"/api/ready">>) ->
    handle_health_route(Socket);
handle_route(Socket, <<"/api/live">>) ->
    gleamunison_http_util:send_json(Socket, 200, <<"{\"live\":true}">>);
handle_route(Socket, Path) ->
    gleamunison_http_routes:serve_static(Socket, Path).

handle_health_route(Socket) ->
    {Status, Json} = gleamunison_readiness:http_response(),
    gleamunison_http_util:send_json(Socket, Status, Json).
