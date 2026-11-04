-module(gleamunison_generation_test).
-export([start_completion_server/1]).

%% One loopback completion for MCP -> provider -> admission integration tests.
%% The caller supplies content; no real provider or credential is involved.
start_completion_server(Content) when is_binary(Content) ->
    {ok, LSock} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true},
                                     {packet, http_bin}, {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(LSock),
    spawn(fun() -> accept(LSock, Content) end),
    {ok, Port}.

accept(LSock, Content) ->
    case gen_tcp:accept(LSock, 10000) of
        {ok, Sock} ->
            headers(Sock, Content, 0),
            gen_tcp:close(Sock);
        {error, _} -> ok
    end,
    gen_tcp:close(LSock),
    ok.

headers(Sock, Content, Length) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, {http_request, _, _, _}} -> headers(Sock, Content, Length);
        {ok, {http_header, _, Name, _, Value}} ->
            case string:lowercase(header_name(Name)) of
                <<"content-length">> ->
                    headers(Sock, Content, binary_to_integer(iolist_to_binary(Value)));
                _ -> headers(Sock, Content, Length)
            end;
        {ok, http_eoh} ->
            inet:setopts(Sock, [{packet, raw}]),
            case Length of
                0 -> ok;
                _ -> {ok, _} = gen_tcp:recv(Sock, Length, 5000)
            end,
            gen_tcp:send(Sock, response(Content));
        _ -> ok
    end.

response(Content) ->
    Quoted = gleamunison_ffi:json_quote(Content),
    Prefix = <<"{\"choices\":[{\"message\":{\"content\":">>,
    Suffix = <<"}}],\"model\":\"local-test\",\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1}}">>,
    Body = iolist_to_binary([Prefix, Quoted, Suffix]),
    iolist_to_binary([
        <<"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ">>,
        integer_to_binary(byte_size(Body)),
        <<"\r\nconnection: close\r\n\r\n">>, Body
    ]).

header_name(Name) when is_atom(Name) -> atom_to_binary(Name, utf8);
header_name(Name) when is_binary(Name) -> Name;
header_name(Name) when is_list(Name) -> list_to_binary(Name).
