-module(gleamunison_http_routes).
-include_lib("kernel/include/file.hrl").
-export([handle_eval_route/2, handle_counter_route/1, handle_define_route/2, handle_browse_route/1,
         serve_static/2, handle_status_route/1, handle_static_file/2, handle_sse_route/1,
         handle_processes_route/1, handle_sync_status_route/1, handle_redefinitions_route/1,
         handle_logs_route/1, handle_enhanced_modules_route/1]).

handle_eval_route(Socket, <<"?expr=", Expr/binary>>) ->
    handle_eval_route(Socket, Expr);
handle_eval_route(Socket, Expr) when is_binary(Expr) ->
    Decoded = gleamunison_http_util:url_decode(Expr),
    case gleamunison_ffi:eval_expression(Decoded) of
        {ok, Result} ->
            gleamunison_http_util:notify_sse_eval(Expr, Result),
            Json = <<"{\"result\":", (gleamunison_http_util:escape_json(Result))/binary, "}">>,
            gleamunison_http_util:send_json(Socket, 200, Json);
        {error, Error} ->
            Json = <<"{\"error\":", (gleamunison_http_util:escape_json(Error))/binary, "}">>,
            gleamunison_http_util:send_json(Socket, 400, Json)
    end;
handle_eval_route(Socket, _) ->
    gleamunison_http_util:send_json(Socket, 400, <<"{\"error\":\"missing expr parameter\"}">>).

handle_counter_route(Socket) ->
    Val = try ets:update_counter(gleamunison_http_counter, count, {2, 1}, {count, 0}) catch _:_ -> 0 end,
    Json = iolist_to_binary(io_lib:format("{\"count\":~p}", [Val])),
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_define_route(Socket, <<"?name=", Rest/binary>>) ->
    case binary:split(Rest, <<"&expr=">>) of
        [Name, Expr] ->
            DecodedName = gleamunison_http_util:url_decode(Name),
            DecodedExpr = gleamunison_http_util:url_decode(Expr),
            case gleamunison_ffi:eval_expression(DecodedExpr) of
                {ok, Result} ->
                    persistent_term:put({gleamunison_notebook, DecodedName}, DecodedExpr),
                    Keys = case persistent_term:get({gleamunison_notebook_keys}, []) of
                        undefined -> [DecodedName];
                        Ks -> lists:usort([DecodedName | Ks])
                    end,
                    persistent_term:put({gleamunison_notebook_keys}, Keys),
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
handle_define_route(Socket, _) ->
    gleamunison_http_util:send_json(Socket, 400, <<"{\"error\":\"missing name or expr parameter\"}">>).

handle_browse_route(Socket) ->
    Keys = case persistent_term:get({gleamunison_notebook_keys}, []) of
        undefined -> [];
        Ks -> Ks
    end,
    Entries = lists:map(fun(Name) ->
        Expr = case persistent_term:get({gleamunison_notebook, Name}, undefined) of
            undefined -> <<"unknown">>;
            V -> V
        end,
        {Name, Expr}
    end, Keys),
    JsonParts = lists:map(fun({Name, Expr}) ->
        EscName = gleamunison_http_util:escape_json(Name),
        EscExpr = gleamunison_http_util:escape_json(Expr),
        <<"{\"name\":", EscName/binary, ",\"expr\":", EscExpr/binary, "}">>
    end, Entries),
    Json = <<"{\"defs\":[", (binary:join(JsonParts, <<",">>))/binary, "]}">>,
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
    ModsJson = <<"[", (binary:join(EscapedMods, <<",">>))/binary, "]">>,
    Json = iolist_to_binary(io_lib:format(
        "{\"node\":\"~s\",\"os\":\"~s\",\"memory_mb\":~p,\"uptime_sec\":~p,\"loaded_modules\":~s}",
        [NodeName, OS, MemoryMB, UptimeSec, ModsJson]
    )),
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_static_file(Socket, FilePath) ->
    case binary:match(FilePath, <<"../">>) of
        nomatch ->
            FullPath = filename:join(["priv", "static", FilePath]),
            case file:read_file(FullPath) of
                {ok, Content} ->
                    Mime = gleamunison_http_util:mime_type(FilePath),
                    gleamunison_http_util:send_file_response(Socket, 200, Mime, Content);
                {error, _} ->
                    gleamunison_http_util:send_response(Socket, 404, <<"Not Found">>)
            end;
        _ ->
            gleamunison_http_util:send_response(Socket, 403, <<"Forbidden">>)
    end.

handle_sse_route(Socket) ->
    Headers = <<"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n">>,
    gen_tcp:send(Socket, Headers),
    Pid = self(),
    try ets:whereis(gleamunison_sse_clients) of
        undefined ->
            ets:new(gleamunison_sse_clients, [set, public, named_table])
    catch _:_ -> ok end,
    ets:insert(gleamunison_sse_clients, {Pid, true}),
    Ref = erlang:monitor(process, Socket),
    sse_keepalive_loop(Socket, Pid, Ref).

sse_keepalive_loop(Socket, Pid, Ref) ->
    receive
        {'DOWN', Ref, process, _Socket, _Reason} ->
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
        [binary:join(Parts, <<",">>), length(Procs), TotalMem])),
    gleamunison_http_util:send_json(Socket, 200, Json).

pid_to_binary(Pid) ->
    list_to_binary(pid_to_list(Pid)).

handle_sync_status_route(Socket) ->
    LoadedMods = length([M || {M, _} <- code:all_loaded(), lists:prefix("m_", atom_to_list(M))]),
    BeamCount = length([F || {_M, F} <- code:all_loaded(), filename:extension(F) =:= ".beam"]),
    Keys = case persistent_term:get({gleamunison_notebook_keys}, []) of
        undefined -> [];
        Ks -> Ks
    end,
    Json = iolist_to_binary(io_lib:format(
        "{\"genesis_count\":52,\"notebook_defs\":~p,\"loaded_modules\":~p,\"beams_loaded\":~p}",
        [length(Keys), LoadedMods, BeamCount])),
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_redefinitions_route(Socket) ->
    Events = case ets:whereis(gleamunison_redefs) of
        undefined -> [];
        _ -> lists:sublist(lists:reverse(ets:tab2list(gleamunison_redefs)), 20)
    end,
    Parts = [iolist_to_binary(io_lib:format(
        "{\"timestamp\":\"~s\",\"name\":\"~s\",\"old_hash\":\"~s\",\"new_hash\":\"~s\",\"elapsed_ms\":~p}",
        [gleamunison_http_util:escape_json(TS), Name, OH, NH, Elapsed]))
        || {TS, Name, OH, NH, Elapsed} <- Events],
    Json = <<"{\"events\":[", (binary:join(Parts, <<",">>))/binary, "]}">>,
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_logs_route(Socket) ->
    Entries = case ets:whereis(gleamunison_logs) of
        undefined -> [];
        _ -> lists:sublist(lists:reverse(ets:tab2list(gleamunison_logs)), 50)
    end,
    Parts = [iolist_to_binary(io_lib:format(
        "{\"timestamp\":\"~s\",\"level\":\"~s\",\"message\":~ts}",
        [gleamunison_http_util:escape_json(TS), Level, gleamunison_http_util:escape_json(Msg)]))
        || {TS, Level, Msg} <- Entries],
    Json = <<"{\"entries\":[", (binary:join(Parts, <<",">>))/binary, "]}">>,
    gleamunison_http_util:send_json(Socket, 200, Json).

handle_enhanced_modules_route(Socket) ->
    Mods = [{atom_to_binary(M, utf8), 
             safe_beam_size(F),
             modified_ts(F),
             atom_to_binary(M, utf8)}
            || {M, F} <- code:all_loaded(), lists:prefix("m_", atom_to_list(M))],
    Parts = [iolist_to_binary(io_lib:format(
        "{\"name\":\"~s\",\"hash\":\"~s\",\"beam_size_bytes\":~p,\"compiled_at\":\"~s\",\"diagnostics\":\"ok\"}",
        [M, M, Size, TS]))
        || {M, Size, TS, _} <- Mods],
    Json = <<"{\"modules\":[", (binary:join(Parts, <<",">>))/binary, "]}">>,
    gleamunison_http_util:send_json(Socket, 200, Json).

safe_beam_size(Path) ->
    case filelib:file_size(Path) of
        N when is_integer(N) -> N;
        _ -> 0
    end.

modified_ts(Path) ->
    case file:read_file_info(Path) of
        {ok, #file_info{mtime = {{Y, Mo, D}, {H, Mi, S}}}} ->
            iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S]));
        _ -> <<"unknown">>
    end.
