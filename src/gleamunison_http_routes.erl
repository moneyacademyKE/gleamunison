-module(gleamunison_http_routes).
-export([handle_eval_route/2, handle_define_route/2, handle_browse_route/1,
         handle_mcp_route/2, serve_static/2, handle_status_route/1, handle_static_file/2, handle_sse_route/1,
         handle_processes_route/1, handle_sync_status_route/1,
         handle_logs_route/1, handle_observability_route/1,
         handle_traces_route/1, handle_trace_detail_route/2, handle_app_route/3]).

-define(MAX_SSE_CLIENTS, 32).

is_localhost(Socket) ->
    case inet:peername(Socket) of
        {ok, {{127, 0, 0, 1}, _}} -> true;
        {ok, {{0, 0, 0, 0, 0, 0, 0, 1}, _}} -> true;
        _ -> false
    end.

handle_eval_route(Socket, <<"?expr=", Expr/binary>>) ->
    handle_eval_route(Socket, Expr);
handle_eval_route(Socket, Expr) when is_binary(Expr) ->
    admit_execution(Socket, fun() -> handle_eval_admitted(Socket, Expr) end);
handle_eval_route(Socket, _) ->
    gleamunison_http_util:send_json(Socket, 400, <<"{\"error\":\"missing expr parameter\"}">>).

%% One admission gate for every route that evaluates caller-supplied code.
%% The policy lives in gleamunison/sandbox_policy.gleam and the profile name
%% comes from gleamunison@config:resolve_profile/0 — the one resolver owning
%% CLI -> TOML -> env -> "local" precedence (empty string means unset), read
%% per request, never cached at boot. This module only reports the refusal;
%% a malformed config file fails closed.
sandbox_admits() ->
    case gleamunison@config:resolve_profile() of
        {ok, Profile} ->
            try gleamunison@sandbox_policy:admit_profile(Profile) of
                {ok, _} -> ok;
                {error, Refusal} when is_binary(Refusal) -> {error, Refusal};
                _ -> {error, <<"sandbox_admission_failed">>}
            catch
                _:_ -> {error, <<"sandbox_admission_failed">>}
            end;
        {error, Reason} -> {error, <<"profile_config_error: ", Reason/binary>>}
    end.

handle_eval_admitted(Socket, Expr) ->
    case is_localhost(Socket) of
        true ->
            Decoded = gleamunison_http_util:url_decode(Expr),
            %% One live session owns the baseline and every define, so a name
            %% defined here is visible to the next eval — the same contract the
            %% REPL and the MCP session already give.
            case gleamunison_web_session:eval(Decoded) of
                {ok, Result} ->
                    gleamunison_http_util:notify_sse_eval(Expr, Result),
                    Json = <<"{\"result\":", (gleamunison_http_util:escape_json(Result))/binary, "}">>,
                    gleamunison_http_util:send_json(Socket, 200, Json);
                {error, Error} ->
                    Json = <<"{\"error\":", (gleamunison_http_util:escape_json(Error))/binary, "}">>,
                    gleamunison_http_util:send_json(Socket, 400, Json)
            end;
        false ->
            gleamunison_http_util:send_response(Socket, 403, <<"Forbidden">>)
    end.

admit_execution(Socket, Work) ->
    case sandbox_admits() of
        {error, Refusal} ->
            gleamunison_http_util:send_json(Socket, 403,
                <<"{\"error\":\"sandbox_refused\",\"detail\":", (gleamunison_http_util:escape_json(Refusal))/binary, "}">>);
        ok -> Work()
    end.

handle_app_route(Socket, Target, Body) ->
    %% The same execution profile as /eval and /mcp, checked before storage.
    admit_execution(Socket, fun() ->
        case gleamunison@active_storage:active_or_open() of
            {ok, Adapter} ->
                case gleamunison@cli_lifecycle:resolve_branch() of
                    {ok, Branch} ->
                        {response, Status, Json} =
                            gleamunison@app_route:request(Adapter, Branch, Target, Body),
                        gleamunison_http_util:send_json(Socket, Status, Json);
                    {error, Reason} ->
                        gleamunison_http_util:send_json(Socket, 500,
                            <<"{\"error\":\"config_invalid\",\"detail\":", (gleamunison_http_util:escape_json(Reason))/binary, "}">>)
                end;
            {error, _Reason} ->
                gleamunison_http_util:send_json(Socket, 503,
                    <<"{\"error\":\"storage_unavailable\"}">>)
        end
    end).

handle_mcp_route(Socket, Body) ->
    admit_execution(Socket, fun() -> handle_mcp_admitted(Socket, Body) end).

handle_mcp_admitted(Socket, Body) ->
    case whereis(gleamunison_mcp_session) of
        undefined ->
            gleamunison_http_util:send_json(
                Socket, 503, <<"{\"error\":\"mcp session not running\"}">>);
        _Pid ->
            case try gen_server:call(gleamunison_mcp_session, {rpc, Body}, 30000) of
                RpcResult -> RpcResult
            catch
                exit:Reason -> {'EXIT', Reason}
            end of
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

handle_define_route(Socket, <<"?name=", Rest/binary>>) ->
    admit_execution(Socket, fun() -> handle_define_admitted(Socket, Rest) end);
handle_define_route(Socket, _) ->
    gleamunison_http_util:send_json(Socket, 400, <<"{\"error\":\"missing name or expr parameter\"}">>).

handle_define_admitted(Socket, Rest) ->
    case is_localhost(Socket) of
        true ->
            case binary:split(Rest, <<"&expr=">>) of
                [Name, Expr] ->
                    DecodedName = gleamunison_http_util:url_decode(Name),
                    DecodedExpr = gleamunison_http_util:url_decode(Expr),
                    %% A define binds the name in the live session. Storing the
                    %% source text and reporting success made the route claim
                    %% something the evaluator never did.
                    case gleamunison_web_session:define(DecodedName, DecodedExpr) of
                        {ok, Result} ->
                            gleamunison_http_util:notify_sse_def(DecodedName),
                            Json = iolist_to_binary(io_lib:format(
                                "{\"status\":\"defined\",\"name\":~ts,\"result\":~ts}",
                                [gleamunison_http_util:escape_json(DecodedName),
                                 gleamunison_http_util:escape_json(Result)]
                            )),
                            gleamunison_http_util:send_json(Socket, 200, Json);
                        {error, Error} ->
                            Json = iolist_to_binary(io_lib:format(
                                "{\"error\":~ts}", [gleamunison_http_util:escape_json(Error)]
                            )),
                            gleamunison_http_util:send_json(Socket, 400, Json)
                    end;
                _ ->
                    gleamunison_http_util:send_json(Socket, 400, <<"{\"error\":\"missing name or expr parameter\"}">>)
            end;
        false ->
            gleamunison_http_util:send_response(Socket, 403, <<"Forbidden">>)
    end.

handle_browse_route(Socket) ->
    %% MCP and HTTP return the same definition metadata and origin.
    Catalog = case gleamunison_web_session:definition_catalog() of
        {ok, CatalogJson} -> CatalogJson;
        _ -> <<"[]">>
    end,
    Json = <<"{\"defs\":", Catalog/binary, "}">>,
    gleamunison_http_util:send_json(Socket, 200, Json).

serve_static(Socket, <<"/">>) ->
    gleamunison_http_util:send_response(Socket, 200, gleamunison_http_util:index_html());
serve_static(Socket, <<"/index.html">>) ->
    gleamunison_http_util:send_response(Socket, 200, gleamunison_http_util:index_html());
serve_static(Socket, <<"/static/", FilePath/binary>>) ->
    handle_static_file(Socket, FilePath);
serve_static(Socket, _Path) ->
    gleamunison_http_util:send_response(Socket, 404, <<"Not Found">>).

handle_status_route(Socket) ->
    NodeName = atom_to_binary(node(), utf8),
    OS = case os:type() of
        {unix, Name} -> atom_to_binary(Name, utf8);
        {win32, _} -> <<"windows">>;
        _ -> <<"unknown">>
    end,
    MemoryMB = erlang:memory(total) div 1024 div 1024,
    {WallClock, _} = erlang:statistics(wall_clock),
    UptimeSec = WallClock div 1000,
    LoadedMods = [atom_to_binary(M, utf8) || {M, _} <- code:all_loaded(),
                    lists:prefix("m_", atom_to_list(M))],
    EscapedMods = [<< "\"", M/binary, "\"" >> || M <- LoadedMods],
    ModsJson = <<"[", (iolist_to_binary(lists:join(<<",">>, EscapedMods)))/binary, "]">>,
    Json = iolist_to_binary(io_lib:format(
        "{\"node\":\"~s\",\"os\":\"~s\",\"memory_mb\":~p,\"uptime_sec\":~p,\"loaded_modules\":~s}",
        [NodeName, OS, MemoryMB, UptimeSec, ModsJson]
    )),
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_static_file(Socket, FilePath) ->
    case gleamunison_static:read(FilePath) of
        {ok, Content} ->
            Mime = gleamunison_http_util:mime_type(FilePath),
            gleamunison_http_util:send_file_response(Socket, 200, Mime, Content);
        {error, forbidden} ->
            gleamunison_http_util:send_response(Socket, 403, <<"Forbidden">>);
        {error, _} ->
            gleamunison_http_util:send_response(Socket, 404, <<"Not Found">>)
    end.

handle_sse_route(Socket) ->
    gleamunison_tables:ensure(gleamunison_sse_clients, [set, public, named_table]),
    case ets:info(gleamunison_sse_clients, size) < ?MAX_SSE_CLIENTS of
        false ->
            gleamunison_http_util:send_json(Socket, 503, <<"{\"error\":\"sse client limit reached\"}">>);
        true ->
            Headers = <<"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n">>,
            gen_tcp:send(Socket, Headers),
            Pid = self(),
            ets:insert(gleamunison_sse_clients, {Pid, true}),
            Ref = erlang:monitor(port, Socket),
            sse_keepalive_loop(Socket, Pid, Ref)
    end.

sse_keepalive_loop(Socket, Pid, Ref) ->
    receive
        {'DOWN', Ref, port, _Socket, _Reason} ->
            ets:delete(gleamunison_sse_clients, Pid),
            ok;
        {sse_event, EventType, Data} ->
            Msg = iolist_to_binary(["event: ", EventType, "\ndata: ", Data, "\n\n"]),
            gen_tcp:send(Socket, Msg),
            sse_keepalive_loop(Socket, Pid, Ref);
        keepalive ->
            gen_tcp:send(Socket, <<": keepalive\n\n">>),
            erlang:send_after(15000, self(), keepalive),
            sse_keepalive_loop(Socket, Pid, Ref)
    after 100 ->
        erlang:send_after(15000, self(), keepalive),
        sse_keepalive_loop(Socket, Pid, Ref)
    end.

handle_processes_route(Socket) ->
    Procs = [{pid_to_binary(P), 
              case process_info(P, registered_name) of {registered_name, N} when is_atom(N) -> atom_to_binary(N, utf8); _ -> <<"-">> end,
              case process_info(P, reductions) of {reductions, R} -> R; _ -> 0 end,
              case process_info(P, memory) of {memory, M} -> M div 1024; _ -> 0 end,
              case process_info(P, message_queue_len) of {message_queue_len, Q} -> Q; _ -> 0 end,
              case process_info(P, status) of {status, S} -> atom_to_binary(S, utf8); _ -> <<"unknown">> end
             } || P <- erlang:processes()],
    TotalMem = lists:sum([M || {_, _, _, M, _, _} <- Procs]),
    Parts = [begin
        iolist_to_binary(io_lib:format(
            "{\"pid\":\"~s\",\"name\":\"~s\",\"reductions\":~p,\"memory_kb\":~p,\"queue_len\":~p,\"status\":\"~s\"}",
            [Pid, Name, Red, Mem, Q, Status]))
    end || {Pid, Name, Red, Mem, Q, Status} <- Procs],
    Json = iolist_to_binary(io_lib:format(
        "{\"processes\":[~s],\"total_count\":~p,\"total_memory_kb\":~p}",
        [iolist_to_binary(lists:join(<<",">>, Parts)), length(Procs), TotalMem])),
    gleamunison_http_util:send_json(Socket, 200, Json).

pid_to_binary(Pid) ->
    list_to_binary(pid_to_list(Pid)).

handle_sync_status_route(Socket) ->
    LoadedMods = length([M || {M, _} <- code:all_loaded(), lists:prefix("m_", atom_to_list(M))]),
    BeamCount = length([F || {_M, F} <- code:all_loaded(), filename:extension(F) =:= ".beam"]),
    Keys = case gleamunison_web_session:definitions() of
        {ok, Names} -> Names;
        _ -> []
    end,
    %% The sync port is the one fact a peer needs to dial this node, so it is
    %% reported where an operator looks. null means no listener, not port 0.
    SyncPort = case whereis(gleamunison_tcp_sync) of
        undefined -> <<"null">>;
        _ -> integer_to_binary(gleamunison_tcp_sync:get_port())
    end,
    Json = iolist_to_binary(io_lib:format(
        "{\"genesis_count\":~p,\"notebook_defs\":~p,\"loaded_modules\":~p,\"beams_loaded\":~p,\"sync_port\":~s}",
        [length(gleamunison@bootstraps:get_init_defs_data()), length(Keys), LoadedMods, BeamCount, SyncPort])),
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_logs_route(Socket) ->
    Entries = gleamunison_log:recent(50),
    %% escape_json/1 already returns a quoted, escaped string: wrapping it in
    %% another pair of quotes produced "timestamp":""2026-..."", which no
    %% JSON parser accepts.
    Parts = [iolist_to_binary(io_lib:format(
        "{\"timestamp\":~ts,\"level\":~ts,\"message\":~ts}",
        [gleamunison_http_util:escape_json(TS), gleamunison_http_util:escape_json(Level), gleamunison_http_util:escape_json(Msg)]))
        || {_Seq, TS, Level, Msg, _Context} <- Entries],
    Json = <<"{\"entries\":[", (iolist_to_binary(lists:join(<<",">>, Parts)))/binary, "]}">>,
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_observability_route(Socket) ->
    gleamunison_http_util:send_json(Socket, 200, gleamunison_observability:export_json()).

handle_traces_route(Socket) ->
    gleamunison_trace:start_trace(),
    Traces = gleamunison_trace:list_traces(),
    Parts = [format_trace(T) || T <- Traces],
    Json = <<"{\"traces\":[", (iolist_to_binary(lists:join(<<",">>, Parts)))/binary, "]}">>,
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_trace_detail_route(Socket, Id) ->
    gleamunison_trace:start_trace(),
    case gleamunison_trace:get_trace(Id) of
        {ok, {TS, Id, Method, Path, Headers}} ->
            HeaderJson = encode_headers(Headers),
            Json = iolist_to_binary(io_lib:format(
                "{\"id\":~ts,\"timestamp\":~ts,\"method\":~ts,\"path\":~ts,\"headers\":~s}",
                [gleamunison_http_util:escape_json(Id),
                 gleamunison_http_util:escape_json(TS),
                 gleamunison_http_util:escape_json(Method),
                 gleamunison_http_util:escape_json(Path),
                 HeaderJson])),
            gleamunison_http_util:send_json(Socket, 200, Json);
        {error, _} ->
            gleamunison_http_util:send_json(Socket, 404, <<"{\"error\":\"not found\"}">>)
    end.

format_trace({TS, Id, Method, Path, _Headers}) ->
    iolist_to_binary(io_lib:format(
        "{\"id\":~ts,\"timestamp\":~ts,\"method\":~ts,\"path\":~ts}",
        [gleamunison_http_util:escape_json(Id),
         gleamunison_http_util:escape_json(TS),
         gleamunison_http_util:escape_json(Method),
         gleamunison_http_util:escape_json(Path)])).

encode_headers(Headers) ->
    %% Header values are redacted at capture, but redaction does not make a
    %% value JSON-safe: a User-Agent carrying a quote still breaks the envelope
    %% unless it goes through the single escaper.
    Parts = [begin
        {K, V} = H,
        iolist_to_binary(io_lib:format("~ts:~ts",
            [gleamunison_http_util:escape_json(K),
             gleamunison_http_util:escape_json(V)]))
    end || H <- Headers],
    <<"{", (iolist_to_binary(lists:join(<<",">>, Parts)))/binary, "}">>.
