-module(latin1_ffi).
-export([start_header_server/0, start_error_server/0]).

%% Latin-1 FFI regression fixtures (bk-8aae), shapes verified against
%% OTP 29.1.1 httpc by probe (2026-10-30):
%%
%% start_header_server/0 replies 200 with a header value carrying raw byte
%% 233 (Latin-1 e-acute). httpc hands the value over as the charlist
%% "caf\xE9"; list_to_binary used to make that invalid UTF-8, so the Gleam
%% side silently saw "".
%%
%% start_error_server/0 replies with a malformed status line, so httpc
%% errors with {invalid_version, "\xE9OT"}; the ~p rendering of that reason
%% used to cross the FFI as invalid UTF-8, so Gleam saw "" instead of it.

start_header_server() ->
    listen(fun(Sock) ->
        drain_request(Sock),
        gen_tcp:send(Sock, <<"HTTP/1.1 200 OK\r\nX-Latin1: caf", 233,
            "\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok">>)
    end).

start_error_server() ->
    listen(fun(Sock) ->
        drain_request(Sock),
        gen_tcp:send(Sock, <<233, "OT HTTP/9.9 junk", 233, "\r\n\r\n">>)
    end).

listen(Responder) ->
    {ok, LSock} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true},
                                     {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(LSock),
    spawn(fun() ->
        case gen_tcp:accept(LSock, 5000) of
            {ok, Sock} -> Responder(Sock), gen_tcp:close(Sock);
            {error, _} -> ok
        end,
        gen_tcp:close(LSock)
    end),
    {ok, Port}.

drain_request(Sock) ->
    _ = gen_tcp:recv(Sock, 0, 500),
    ok.
