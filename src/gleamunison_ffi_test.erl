-module(gleamunison_ffi_test).
-export([test_storage_owner_survives/0, test_effects_runtime/0, test_ffi_io_coverage/0]).
-export([start_echo_server/0]).
-export([start_http_server/1, stop_http_server/0, http_post/3, http_post_auth/4,
         http_post_auth_length/5, set_http_token/1,
         clear_http_token/0, tcp_auth_probe/1, set_eval_timeout/1,
         clear_eval_timeout/0, otp_blake2b64/1]).
-export([pd_counter_inc/1, pd_counter_get/1, pd_record/2, pd_records/1]).
-export([rescue/1]).

%% Run a zero-arg fun and capture any raised reason as {error, Rendered}.
%% House pattern for asserting structured denials (capability gates) without
%% crashing the test process.
rescue(F) when is_function(F, 0) ->
    try F() of
        R -> {ok, R}
    catch
        Class:Reason -> {error, iolist_to_binary(io_lib:format("~p:~p", [Class, Reason]))}
    end.

test_storage_owner_survives() ->
    Parent = self(),
    Ref = make_ref(),
    spawn(fun() ->
        Tab = gleamunison_storage:new(),
        Parent ! {Ref, Tab}
    end),
    Tab = receive
        {Ref, T} -> T
    after 1000 ->
        error(timeout)
    end,
    timer:sleep(100),
    {ok, nil} = gleamunison_storage:insert(Tab, <<"mykey">>, <<"myval">>),
    case gleamunison_storage:lookup(Tab, <<"mykey">>) of
        {ok, {some, <<"myval">>}} -> {ok, nil};
        Other -> {error, list_to_binary(io_lib:format("unexpected ~p", [Other]))}
    end.

test_effects_runtime() ->
    Handler = fun(Args, Cont) -> Cont([list_to_binary(lists:reverse(binary_to_list(hd(Args))))]) end,
    Result = gleamunison_effets:handle_comp(
        {<<"ability1">>, Handler},
        fun() ->
            gleamunison_effets:do_op(<<"ability1">>, 0, [<<"hello">>], fun(R) -> R end)
        end
    ),
    case Result of
        [<<"olleh">>] -> {ok, nil};
        Other -> {error, list_to_binary(io_lib:format("unexpected ~p", [Other]))}
    end.

test_ffi_io_coverage() ->
    %% 1. state_get undefined
    {ok, null} = gleamunison_ffi_io:state_get(<<"nonexistent_key">>),

    %% 2. eval_expression parse error
    {error, _} = gleamunison_ffi_io:eval_expression(<<"(">>),

    %% 3. eval_expression exception (division by zero in REPL evaluation)
    {error, _} = gleamunison_ffi_io:eval_expression(<<"(div 1 0)">>),

    %% 4. node_atom and net_adm:ping / rpc:call failures on nonexistent node
    NodeBin = <<"nonexistent@localhost">>,
    nonexistent@localhost = gleamunison_ffi_io:node_atom(NodeBin),
    {error, <<"Connection failed (pang)">>} = gleamunison_ffi_io:sync_connect(NodeBin),
    {error, _} = gleamunison_ffi_io:sync_send_refs(NodeBin, []),
    {error, _} = gleamunison_ffi_io:sync_receive_diff(NodeBin),
    {error, _} = gleamunison_ffi_io:sync_request_defs(NodeBin, []),
    {error, _} = gleamunison_ffi_io:sync_push_defs(NodeBin, []),

    %% 4b. Test TCP fallback when no @ in peer name
    NodeNoAt = <<"localhost:12345">>,
    {error, _} = gleamunison_ffi_io:sync_connect(NodeNoAt),

    %% 5. ensure_table table already exists
    ok = gleamunison_ffi_io:register_peer_refs(node(), []),
    ok = gleamunison_ffi_io:register_peer_refs(node(), []),

    %% 6. compute_diff peer not in ETS
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),

    %% Save active storage state to restore it later
    OldActive = persistent_term:get({gleamunison, active_storage}, undefined),

    %% 7. fetch_defs_binary, receive_pushed_defs, compute_diff when storage undefined
    persistent_term:erase({gleamunison, active_storage}),
    [] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{<<"ab">>, <<"def">>}]),

    %% Test ets lookup/insert/list_refs
    TabETS = gleamunison_storage:new(),
    persistent_term:put({gleamunison, active_storage}, {ets, TabETS}),
    [] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{<<"ab">>, <<"def">>}]),
    [{<<"ab">>, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    {ok, {some, <<"def">>}} = gleamunison_storage:lookup(TabETS, gleamunison_ffi:hex_to_bytes(<<"ab">>)),

    %% Test dets lookup/insert/list_refs
    file:delete("test_dets.db"),
    {error, _} = gleamunison_storage:dets_new(<<".">>),
    {ok, TabDETS} = gleamunison_storage:dets_new(<<"test_dets.db">>),
    persistent_term:put({gleamunison, active_storage}, {dets, TabDETS}),
    [] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{<<"ab">>, <<"def">>}]),
    [{<<"ab">>, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    {ok, {some, <<"def">>}} = gleamunison_storage:dets_lookup(TabDETS, gleamunison_ffi:hex_to_bytes(<<"ab">>)),
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),
    gleamunison_storage:dets_close(TabDETS),
    file:delete("test_dets.db"),

    %% Test partitioned_dets lookup/insert/list_refs
    file:delete("test_pd"),
    {ok, TabPD} = gleamunison_storage:partitioned_dets_new(<<"test_pd">>),
    persistent_term:put({gleamunison, active_storage}, {partitioned_dets, TabPD}),
    [] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{<<"ab">>, <<"def">>}]),
    [{<<"ab">>, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    {ok, {some, <<"def">>}} = gleamunison_storage:partitioned_dets_lookup(TabPD, gleamunison_ffi:hex_to_bytes(<<"ab">>)),
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),
    gleamunison_storage:partitioned_dets_close(TabPD),
    gleamunison_storage:partitioned_dets_delete_file(<<"test_pd">>),

    %% Test mnesia lookup/insert/list_refs
    application:start(mnesia),
    {ok, TabMnesia} = gleamunison_storage:mnesia_new(<<"test_tab">>),
    {ok, TabMnesia} = gleamunison_storage:mnesia_new(<<"test_tab">>),
    persistent_term:put({gleamunison, active_storage}, {mnesia, TabMnesia}),
    [] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{<<"ab">>, <<"def">>}]),
    [{<<"ab">>, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([<<"ab">>]),
    {ok, {some, <<"def">>}} = gleamunison_storage:mnesia_lookup(TabMnesia, gleamunison_ffi:hex_to_bytes(<<"ab">>)),
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),
    application:stop(mnesia),

    %% Restore active storage
    case OldActive of
        undefined -> persistent_term:erase({gleamunison, active_storage});
        _ -> persistent_term:put({gleamunison, active_storage}, OldActive)
    end,

    %% 8. ref_to_hex and hex_to_ref
    Hex = <<"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef">>,
    Ref = {ref, {hash, gleamunison_ffi:hex_to_bytes(Hex)}},
    Ref = gleamunison_ffi_io:hex_to_ref(Hex),
    Hex = gleamunison_ffi_io:ref_to_hex(Ref),
    Hex = gleamunison_ffi_io:ref_to_hex(gleamunison_ffi:hex_to_bytes(Hex)),

    %% 9. Test gleamunison_config env lookup
    {error, nil} = gleamunison_config:get_env(<<"NONEXISTENT_ENV_VAR_12345">>),
    _AllEnvs = gleamunison_config:get_all_env(),
    os:putenv("TEST_ENV_VAR_12345", "val"),
    {ok, <<"val">>} = gleamunison_config:get_env(<<"TEST_ENV_VAR_12345">>),

    %% 10. Test gleamunison_crypto algorithm and hashing paths
    Bin = <<"hello">>,
    {ok, _H} = gleamunison_crypto:hash(<<"sha256">>, Bin),
    {ok, _H2} = gleamunison_crypto:hash(<<"sha512">>, Bin),
    {ok, _H3} = gleamunison_crypto:hash(<<"md5">>, Bin),
    {ok, _H4} = gleamunison_crypto:hash(<<"invalid_algo">>, Bin),
    {ok, _Mac} = gleamunison_crypto:hmac(<<"sha256">>, <<"key">>, Bin),
    _Rand = gleamunison_crypto:random_bytes(16),
    <<>> = gleamunison_crypto:random_bytes(0),
    _EHex = gleamunison_crypto:hash_to_hex(Bin),

    %% Test list string algorithm representation in crypto
    {ok, _L1} = gleamunison_crypto:hash("sha256", Bin),
    {ok, _L2} = gleamunison_crypto:hash("sha512", Bin),
    {ok, _L3} = gleamunison_crypto:hash("md5", Bin),

    %% Test catch blocks in crypto
    {error, <<"hash failed">>} = gleamunison_crypto:hash(<<"trigger_error">>, Bin),
    {error, <<"hmac failed">>} = gleamunison_crypto:hmac(<<"trigger_error">>, <<"key">>, Bin),

    {ok, nil}.

%% One-shot HTTP echo server for tests: accepts a single request, replies 200
%% with a body describing exactly what the server received (headers + body).
start_echo_server() ->
    {ok, _} = application:ensure_all_started(inets),
    case whereis(gleamunison_echo_test) of
        undefined -> ok;
        _ -> erlang:error({echo_server_busy, gleamunison_echo_test})
    end,
    {ok, LSock} = gen_tcp:listen(0, [
        binary, {active, false}, {reuseaddr, true},
        {packet, http_bin}, {ip, {127, 0, 0, 1}}
    ]),
    {ok, Port} = inet:port(LSock),
    Pid = spawn(fun() -> echo_accept(LSock) end),
    register(gleamunison_echo_test, Pid),
    {ok, Port}.

echo_accept(LSock) ->
    case gen_tcp:accept(LSock, 10000) of
        {ok, Sock} ->
            echo_collect(Sock, []),
            gen_tcp:close(Sock);
        {error, _} -> ok
    end,
    gen_tcp:close(LSock),
    unregister(gleamunison_echo_test),
    ok.

echo_collect(Sock, Headers) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, {http_request, _Method, _Path, _V}} ->
            echo_collect(Sock, Headers);
        {ok, {http_header, _, Name, _, Value}} ->
            echo_collect(Sock, [{Name, Value} | Headers]);
        {ok, http_eoh} ->
            Len = echo_content_length(Headers, 0),
            inet:setopts(Sock, [{packet, raw}]),
            Body = case Len of
                0 -> <<>>;
                _ ->
                    case gen_tcp:recv(Sock, Len, 5000) of
                        {ok, B} -> B;
                        _ -> <<>>
                    end
            end,
            HeaderTxt = iolist_to_binary([
                [echo_name(K), <<": ">>, V, <<"\n">>]
             || {K, V} <- lists:reverse(Headers)
            ]),
            RespBody = <<HeaderTxt/binary, <<"BODY:">>/binary, Body/binary>>,
            Resp = iolist_to_binary([
                <<"HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: ">>,
                integer_to_binary(byte_size(RespBody)),
                <<"\r\nconnection: close\r\n\r\n">>,
                RespBody
            ]),
            gen_tcp:send(Sock, Resp),
            ok;
        _ -> ok
    end.

echo_content_length([{K, V} | Rest], _Acc) ->
    case string:lowercase(echo_name(K)) of
        <<"content-length">> ->
            binary_to_integer(iolist_to_binary(V));
        _ -> echo_content_length(Rest, _Acc)
    end;
echo_content_length([], Acc) -> Acc.

echo_name(K) when is_atom(K) -> atom_to_binary(K, utf8);
echo_name(K) when is_binary(K) -> K;
echo_name(K) when is_list(K) -> list_to_binary(K).

%% Test-grade mutable cells via the process dictionary (each gleeunit test
%% runs in one process, so scripted handlers can count and record).
pd_counter_inc(Key) ->
    N = case erlang:get({pd_counter, Key}) of
        undefined -> 1;
        M when is_integer(M) -> M + 1
    end,
    erlang:put({pd_counter, Key}, N),
    N.

pd_counter_get(Key) ->
    case erlang:get({pd_counter, Key}) of
        undefined -> 0;
        M -> M
    end.

pd_record(Key, Value) ->
    Old = case erlang:get({pd_records, Key}) of
        undefined -> [];
        L -> L
    end,
    erlang:put({pd_records, Key}, [Value | Old]),
    nil.

pd_records(Key) ->
    case erlang:get({pd_records, Key}) of
        undefined -> [];
        L -> lists:reverse(L)
    end.

tcp_auth_probe(Mode) when is_integer(Mode) ->
    true = os:putenv("GLEAMUNISON_SYNC_TOKEN", "server-secret"),
    ensure_tcp_sync_server(),
    Port = gleamunison_tcp_sync:get_port(),
    SocketResult = case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 2000) of
        {ok, Socket} ->
            case Mode of
                3 ->
                    ok = gen_tcp:send(Socket, <<1048577:32>>),
                    receive_raw_reply(Socket);
                _ ->
                    Message = {<<"test-peer">>, {connect, <<"test-peer">>}},
                    Request = case Mode of
                        0 -> Message;
                        1 -> {auth, <<"server-secret">>, Message};
                        2 -> {auth, <<"wrong-secret">>, Message}
                    end,
                    Bin = term_to_binary(Request),
                    ok = gen_tcp:send(Socket, <<(byte_size(Bin)):32, Bin/binary>>),
                    receive_raw_reply(Socket)
            end;
        {error, Reason} -> {error, Reason}
    end,
    true = os:unsetenv("GLEAMUNISON_SYNC_TOKEN"),
    list_to_binary(io_lib:format("~tp", [SocketResult])).

ensure_tcp_sync_server() ->
    case whereis(gleamunison_tcp_sync) of
        undefined ->
            {ok, _Pid} = gleamunison_tcp_sync:start_link(),
            ok;
        _Pid -> ok
    end.

receive_raw_reply(Socket) ->
    Result = case gen_tcp:recv(Socket, 4, 2000) of
        {ok, <<Len:32>>} ->
            case gen_tcp:recv(Socket, Len, 2000) of
                {ok, Bin} ->
                    try binary_to_term(Bin, [safe]) catch _:_ -> invalid_reply end;
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} -> {error, Reason}
    end,
    gen_tcp:close(Socket),
    Result.

set_eval_timeout(Value) when is_integer(Value) ->
    true = os:putenv("GLEAMUNISON_EVAL_TIMEOUT_MS", integer_to_list(Value)),
    nil.

clear_eval_timeout() ->
    true = os:unsetenv("GLEAMUNISON_EVAL_TIMEOUT_MS"),
    nil.

%% Start the real HTTP server on Port, backgrounded, and wait until the
%% listener accepts connections (up to ~1s).
start_http_server(Port) ->
    spawn(fun() -> gleamunison_http:start_server(Port) end),
    wait_for_port(Port, 10),
    nil.

stop_http_server() ->
    gleamunison_http:stop_server(),
    nil.

wait_for_port(_Port, 0) -> ok;
wait_for_port(Port, N) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 200) of
        {ok, S} -> gen_tcp:close(S), ok;
        {error, _} -> timer:sleep(100), wait_for_port(Port, N - 1)
    end.

%% Raw POST client: sends Body with Content-Length, returns {Status, RespBody}.
http_post(Port, Path, Body) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 2000) of
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format("connect: ~p", [Reason]))};
        {ok, Socket} ->
            Req = iolist_to_binary(io_lib:format(
                "POST ~s HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: ~p\r\nConnection: close\r\n\r\n~s",
                [Path, byte_size(Body), Body])),
            ok = gen_tcp:send(Socket, Req),
            Result = recv_all(Socket, <<>>),
            gen_tcp:close(Socket),
            case Result of
                {ok, Resp} -> parse_http_response(Resp);
                {error, R} ->
                    {error, iolist_to_binary(io_lib:format("recv: ~p", [R]))}
            end
    end.

%% POST variant used by auth and size-limit integration tests.
http_post_auth(Port, Path, Body, Token) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 2000) of
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format("connect: ~p", [Reason]))};
        {ok, Socket} ->
            Req = iolist_to_binary(io_lib:format(
                "POST ~s HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer ~s\r\nContent-Type: application/json\r\nContent-Length: ~p\r\nConnection: close\r\n\r\n~s",
                [Path, Token, byte_size(Body), Body])),
            ok = gen_tcp:send(Socket, Req),
            Result = recv_all(Socket, <<>>),
            gen_tcp:close(Socket),
            case Result of
                {ok, Resp} -> parse_http_response(Resp);
                {error, R} ->
                    {error, iolist_to_binary(io_lib:format("recv: ~p", [R]))}
            end
    end.

%% POST variant with an explicit declared length, used to reject oversized
%% requests before the body is read.
http_post_auth_length(Port, Path, Body, Token, DeclaredLength) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 2000) of
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format("connect: ~p", [Reason]))};
        {ok, Socket} ->
            Req = iolist_to_binary(io_lib:format(
                "POST ~s HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer ~s\r\nContent-Type: application/json\r\nContent-Length: ~p\r\nConnection: close\r\n\r\n~s",
                [Path, Token, DeclaredLength, Body])),
            ok = gen_tcp:send(Socket, Req),
            Result = recv_all(Socket, <<>>),
            gen_tcp:close(Socket),
            case Result of
                {ok, Resp} -> parse_http_response(Resp);
                {error, R} ->
                    {error, iolist_to_binary(io_lib:format("recv: ~p", [R]))}
            end
    end.

set_http_token(Token) when is_binary(Token) ->
    true = os:putenv("GLEAMUNISON_HTTP_TOKEN", binary_to_list(Token)),
    nil.

clear_http_token() ->
    true = os:unsetenv("GLEAMUNISON_HTTP_TOKEN"),
    nil.

recv_all(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Data} -> recv_all(Socket, <<Acc/binary, Data/binary>>);
        {error, closed} -> {ok, Acc};
        {error, Reason} -> {error, Reason}
    end.

%% Native OTP BLAKE2b-64 for cross-checking our pure implementation.
otp_blake2b64(Data) ->
    crypto:hash(blake2b, Data).

parse_http_response(Bin) ->
    case binary:split(Bin, <<"\r\n">>) of
        [StatusLine, Rest] ->
            case binary:split(StatusLine, <<" ">>, [global]) of
                [_, CodeBin | _] ->
                    Status = binary_to_integer(CodeBin),
                    case binary:split(Rest, <<"\r\n\r\n">>) of
                        [_Headers, Body] -> {ok, {Status, Body}};
                        [_] -> {ok, {Status, <<>>}}
                    end;
                _ -> {error, <<"bad status line">>}
            end;
        _ -> {error, <<"bad response">>}
    end.
