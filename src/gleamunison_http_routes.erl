-module(gleamunison_http_routes).
-export([handle_eval_route/2, handle_counter_route/1, handle_define_route/2, handle_browse_route/1, serve_static/2]).

handle_eval_route(Socket, <<"?expr=", Expr/binary>>) ->
    handle_eval_route(Socket, Expr);
handle_eval_route(Socket, Expr) when is_binary(Expr) ->
    Decoded = gleamunison_http_util:url_decode(Expr),
    case gleamunison_ffi:eval_expression(Decoded) of
        {ok, Result} ->
            Json = <<"{\"result\":", (gleamunison_http_util:escape_json(Result))/binary, "}">>,
            gleamunison_http_util:send_json(Socket, 200, Json);
        {error, Error} ->
            Json = <<"{\"error\":", (gleamunison_http_util:escape_json(Error))/binary, "}">>,
            gleamunison_http_util:send_json(Socket, 400, Json)
    end;
handle_eval_route(Socket, _) ->
    gleamunison_http_util:send_json(Socket, 400, <<"{\"error\":\"missing expr parameter\"}">>).

handle_counter_route(Socket) ->
    Val = case catch ets:update_counter(gleamunison_http_counter, count, {2, 1}, {count, 0}) of
        {'EXIT', _} -> 0;
        N -> N
    end,
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
serve_static(Socket, _Path) ->
    gleamunison_http_util:send_response(Socket, 404, <<"Not Found">>).
