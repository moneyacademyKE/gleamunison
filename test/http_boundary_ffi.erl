-module(http_boundary_ffi).
-export([static_paths/0, auth_routes/0, symlink_escape/0]).

with_server(Fun) ->
    Old = os:getenv("GLEAMUNISON_HTTP_TOKEN"),
    os:putenv("GLEAMUNISON_HTTP_TOKEN", "test-boundary-token"),
    gleamunison_ffi_test:start_http_server(18104),
    try Fun()
    after
        gleamunison_ffi_test:stop_http_server(),
        case Old of false -> os:unsetenv("GLEAMUNISON_HTTP_TOKEN"); _ -> os:putenv("GLEAMUNISON_HTTP_TOKEN", Old) end
    end.

static_paths() -> with_server(fun() ->
    Paths = [<<"/static//etc/passwd">>, <<"/static/../gleam.toml">>,
             <<"/static/%2fetc/passwd">>, <<"/static/%2e%2e/%2e%2e/gleam.toml">>,
             <<"/static/..%5c..%5cgleam.toml">>, <<"/static/C:/etc/passwd">>,
             <<"/static/%252e%252e/gleam.toml">>, <<"/static/%00">>],
    lists:all(fun(Path) ->
        Code = get_status(Path, <<>>),
        io:format("static_probe ~s => ~p~n", [Path, Code]),
        Code =:= 403 orelse Code =:= 404
    end, Paths) andalso get_status(<<"/static/js/dashboard.js">>, <<>>) =:= 200
end).

auth_routes() -> with_server(fun() ->
    Protected = [<<"/eval?expr=42">>, <<"/define?name=x&expr=1">>, <<"/mcp">>,
      <<"/browse">>, <<"/counter">>, <<"/api/status">>, <<"/api/events">>,
      <<"/api/processes">>, <<"/api/sync-status">>, <<"/api/redefinitions">>,
      <<"/api/logs">>, <<"/api/modules">>, <<"/api/traces">>, <<"/api/traces/1">>],
    lists:all(fun(Path) ->
        Code = get_status(Path, <<>>),
        io:format("auth_probe ~s => ~p~n", [Path, Code]),
        Code =:= 401 andalso get_status(Path, <<"wrong">>) =:= 401
    end, Protected) andalso get_status(<<"/api/status">>, <<"test-boundary-token">>) =:= 200
      andalso get_status(<<"/api/live">>, <<>>) =:= 200
end).

symlink_escape() -> with_server(fun() ->
    %% A disposable symlink only; never read a host secret to test containment.
    Link = "priv/static/boundary-test-link",
    case file:make_symlink("../../gleam.toml", Link) of
        ok -> try get_status(<<"/static/boundary-test-link">>, <<>>) =:= 403
              after file:delete(Link) end;
        {error, Reason} -> error({symlink_fixture_failed, Reason})
    end
end).

get_status(Path, Token) ->
    {ok, S} = gen_tcp:connect({127,0,0,1}, 18104, [binary, {active, false}, {packet, http_bin}], 2000),
    Auth = case Token of <<>> -> <<>>; _ -> ["Authorization: Bearer ", Token, "\r\n"] end,
    ok = gen_tcp:send(S, ["GET ", Path, " HTTP/1.1\r\nHost: localhost\r\n", Auth, "Connection: close\r\n\r\n"]),
    Reply = gen_tcp:recv(S, 0, 2000),
    gen_tcp:close(S),
    case Reply of {ok, {http_response, _, Code, _}} -> Code; _ -> error({bad_http_reply, Reply}) end.
