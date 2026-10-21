-module(gleamunison_ffi_test).
-export([test_storage_owner_survives/0, test_effects_runtime/0, test_ffi_io_coverage/0]).
-export([start_echo_server/0, start_slow_server/0]).
-export([start_http_server/1, stop_http_server/0, http_post/3, http_post_auth/4,
         http_post_auth_length/5, set_http_token/1,
         clear_http_token/0, tcp_auth_probe/1, set_eval_timeout/1,
         clear_eval_timeout/0, otp_blake2b64/1]).
-export([pd_counter_inc/1, pd_counter_get/1, pd_record/2, pd_records/1]).
-export([metrics_restart_probe/0, http_drain_probe/0, observability_probe/1,
         metrics_name_bound_probe/0, llm_budget_snapshot_json/0, set_env/2, unset_env/1]).
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
    ContentKey = gleamunison_ffi:hash_bytes(<<"def">>),
    ContentHex = gleamunison_ffi_io:ref_to_hex(ContentKey),

    %% 7. fetch_defs_binary, receive_pushed_defs, compute_diff when storage undefined
    persistent_term:erase({gleamunison, active_storage}),
    [] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    {error, <<"storage_unavailable">>} = gleamunison_ffi_io:receive_pushed_defs([{ContentHex, <<"def">>}]),

    %% Test ets lookup/insert/list_refs
    TabETS = gleamunison_storage:new(),
    persistent_term:put({gleamunison, active_storage}, {ets, TabETS}),
    [] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{ContentHex, <<"def">>}]),
    [{ContentHex, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    {ok, {some, <<"def">>}} = gleamunison_storage:lookup(TabETS, ContentKey),

    %% Test dets lookup/insert/list_refs
    file:delete("test_dets.db"),
    {error, _} = gleamunison_storage:dets_new(<<".">>),
    {ok, TabDETS} = gleamunison_storage:dets_new(<<"test_dets.db">>),
    persistent_term:put({gleamunison, active_storage}, {dets, TabDETS}),
    [] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{ContentHex, <<"def">>}]),
    [{ContentHex, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    {ok, {some, <<"def">>}} = gleamunison_storage:dets_lookup(TabDETS, ContentKey),
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),
    gleamunison_storage:dets_close(TabDETS),
    file:delete("test_dets.db"),

    %% Test partitioned_dets lookup/insert/list_refs
    file:delete("test_pd"),
    {ok, TabPD} = gleamunison_storage:partitioned_dets_new(<<"test_pd">>),
    persistent_term:put({gleamunison, active_storage}, {partitioned_dets, TabPD}),
    [] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{ContentHex, <<"def">>}]),
    [{ContentHex, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    {ok, {some, <<"def">>}} = gleamunison_storage:partitioned_dets_lookup(TabPD, ContentKey),
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),
    gleamunison_storage:partitioned_dets_close(TabPD),
    gleamunison_storage:partitioned_dets_delete_file(<<"test_pd">>),

    %% Test mnesia lookup/insert/list_refs
    application:start(mnesia),
    {ok, TabMnesia} = gleamunison_storage:mnesia_new(<<"test_tab">>),
    {ok, TabMnesia} = gleamunison_storage:mnesia_new(<<"test_tab">>),
    persistent_term:put({gleamunison, active_storage}, {mnesia, TabMnesia}),
    [] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    ok = gleamunison_ffi_io:receive_pushed_defs([{ContentHex, <<"def">>}]),
    [{ContentHex, <<"def">>}] = gleamunison_ffi_io:fetch_defs_binary([ContentHex]),
    {ok, {some, <<"def">>}} = gleamunison_storage:mnesia_lookup(TabMnesia, ContentKey),
    _ = gleamunison_ffi_io:compute_diff(nonexistent_peer),
    application:stop(mnesia),

    %% Restore active storage
    case OldActive of
        undefined -> persistent_term:erase({gleamunison, active_storage});
        _ -> persistent_term:put({gleamunison, active_storage}, OldActive)
    end,

    %% 8. ref_to_hex and hex_to_ref
    Hex = <<"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef">>,
    {ok, HexBytes} = gleamunison_ffi:hex_to_bytes(Hex),
    Ref = {ref, {hash, HexBytes}},
    {ok, Ref} = gleamunison_ffi_io:hex_to_ref(Hex),
    Hex = gleamunison_ffi_io:ref_to_hex(Ref),
    Hex = gleamunison_ffi_io:ref_to_hex(HexBytes),

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

start_slow_server() ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, LSock} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true},
                                     {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(LSock),
    spawn(fun() ->
        case gen_tcp:accept(LSock, 2000) of
            {ok, Sock} ->
                timer:sleep(1000),
                gen_tcp:close(Sock);
            {error, _} -> ok
        end,
        gen_tcp:close(LSock)
    end),
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
                4 ->
                    %% Replay: reuse one captured proof frame on a second
                    %% connection — the server nonce differs, so auth must fail.
                    Frame = v2_auth_frame(<<"server-secret">>),
                    ok = gen_tcp:send(Socket, Frame),
                    _Challenge1 = receive_raw_reply_keep(Socket),
                    _First = receive_raw_reply_keep(Socket),
                    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 2000) of
                        {ok, Socket2} ->
                            ok = gen_tcp:send(Socket2, Frame),
                            _Challenge2 = receive_raw_reply_keep(Socket2),
                            receive_raw_reply(Socket2);
                        {error, Reason2} -> {error, Reason2}
                    end;
                _ ->
                    Message = {<<"test-peer">>, {connect, <<"test-peer">>}},
                    case Mode of
                        0 ->
                            Bin = term_to_binary(Message),
                            ok = gen_tcp:send(Socket, <<(byte_size(Bin)):32, Bin/binary>>),
                            receive_raw_reply(Socket);
                        1 -> v2_handshake(Socket, <<"server-secret">>, Message);
                        2 -> v2_handshake(Socket, <<"wrong-secret">>, Message)
                    end
            end;
        {error, Reason} -> {error, Reason}
    end,
    true = os:unsetenv("GLEAMUNISON_SYNC_TOKEN"),
    list_to_binary(io_lib:format("~tp", [SocketResult])).

v2_handshake(Socket, Token, Message) ->
    ClientNonce = crypto:strong_rand_bytes(16),
    send_term(Socket, {hello, ClientNonce}),
    case receive_raw_reply_keep(Socket) of
        {challenge, ServerNonce} ->
            Digest = crypto:hash(sha256, term_to_binary(Message)),
            Proof = crypto:mac(hmac, sha256, Token,
                               <<ClientNonce/binary, ServerNonce/binary, Digest/binary>>),
            send_term(Socket, {auth2, ClientNonce, Proof, Message}),
            receive_raw_reply(Socket);
        Other -> Other
    end.

v2_auth_frame(Token) ->
    %% Fixed nonces make the frame replayable by construction; the server must
    %% still reject it because its challenge nonce is fresh per connection.
    ClientNonce = <<"fixed-client-nonce">>,
    ServerNonce = <<"fixed-server-nonce">>,
    Message = {<<"test-peer">>, {connect, <<"test-peer">>}},
    Digest = crypto:hash(sha256, term_to_binary(Message)),
    Proof = crypto:mac(hmac, sha256, Token,
                       <<ClientNonce/binary, ServerNonce/binary, Digest/binary>>),
    Hello = term_to_binary_with_len({hello, ClientNonce}),
    Auth = term_to_binary_with_len({auth2, ClientNonce, Proof, Message}),
    <<Hello/binary, Auth/binary>>.

send_term(Socket, Term) ->
    Bin = term_to_binary(Term),
    ok = gen_tcp:send(Socket, <<(byte_size(Bin)):32, Bin/binary>>).

term_to_binary_with_len(Term) ->
    Bin = term_to_binary(Term),
    <<(byte_size(Bin)):32, Bin/binary>>.

receive_raw_reply_keep(Socket) ->
    case gen_tcp:recv(Socket, 4, 2000) of
        {ok, <<Len:32>>} ->
            case gen_tcp:recv(Socket, Len, 2000) of
                {ok, Bin} ->
                    try binary_to_term(Bin, [safe]) catch _:_ -> invalid_reply end;
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} -> {error, Reason}
    end.

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

%% Start the real HTTP server on Port in a monitored process and wait until
%% the listener accepts connections (up to ~1s).
start_http_server(Port) ->
    {Pid, Monitor} = spawn_monitor(fun() -> gleamunison_http:start_server(Port) end),
    try
        wait_for_port(Port, 10),
        erlang:demonitor(Monitor, [flush]),
        nil
    catch
        error:Reason ->
            exit(Pid, kill),
            receive {'DOWN', Monitor, process, Pid, _} -> ok after 1000 -> ok end,
            erlang:error(Reason)
    end.

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

%% Crash/restart proof for the metrics cache: the supervisor owns the
%% gen_server with restart=permanent, so a kill must produce a NEW pid and
%% the next record must land without the caller noticing.
metrics_restart_probe() ->
    ok = gleamunison_metrics_sup:ensure_started(),
    Pid = whereis(gleamunison_metrics),
    true = is_pid(Pid),
    exit(Pid, kill),
    NewPid = wait_for_metrics_pid(Pid, 100),
    true = is_pid(NewPid),
    true = NewPid =/= Pid,
    nil = gleamunison_metrics:counter(<<"probe.restart">>, 1),
    true.

wait_for_metrics_pid(Old, 0) -> Old;
wait_for_metrics_pid(Old, N) ->
    case whereis(gleamunison_metrics) of
        undefined -> timer:sleep(10), wait_for_metrics_pid(Old, N - 1);
        Old -> timer:sleep(10), wait_for_metrics_pid(Old, N - 1);
        New -> New
    end.

%% Drain proof: start a server, drain it, then the listener entry must be
%% gone (readiness would report http_not_running) and stop must be clean.
%% start_server blocks for the server's lifetime, so it runs in a spawned
%% process and we poll for the listener registration. Port must be real:
%% gleamunison_http_sup treats 0 as "start no children", and a crashed
%% probe must never leave an empty sup registered behind it.
http_drain_probe() ->
    Port = free_port(),
    _Server = spawn(fun() -> gleamunison_http:start_server(Port) end),
    try
        {HttpPid, _} = wait_for_listener(200),
        drained = gleamunison_http:drain(500),
        undefined = persistent_term:get({gleamunison_http, listener}, undefined),
        true = is_process_alive(HttpPid),
        true
    after
        catch gleamunison_http:stop_server()
    end.

free_port() ->
    {ok, Listen} = gen_tcp:listen(0, []),
    {ok, {_Addr, Port}} = inet:sockname(Listen),
    gen_tcp:close(Listen),
    Port.

wait_for_listener(0) -> error(listener_timeout);
wait_for_listener(N) ->
    case persistent_term:get({gleamunison_http, listener}, undefined) of
        undefined -> timer:sleep(10), wait_for_listener(N - 1);
        Listener -> Listener
    end.

%% Probe the observability export: 1 = json shape, 2 = redaction.
observability_probe(1) ->
    gleamunison_observability:export_json();
observability_probe(2) ->
    Secret = <<"supersecret-probe-token">>,
    {ok, Id} = gleamunison_trace:capture_request(
        <<"GET">>, <<"/probe">>,
        [{<<"authorization">>, Secret}, {<<"cookie">>, <<"session=abc">>}]),
    {ok, {_TS, _Id, _M, _P, Headers}} = gleamunison_trace:get_trace(Id),
    Export = gleamunison_observability:export_json(),
    NoSecretInExport = binary:match(Export, Secret) =:= nomatch,
    NoSecretInTrace = lists:all(
        fun({_K, V}) -> V =/= Secret end, Headers),
    RedactedPresent = lists:any(
        fun({_K, V}) -> V =:= <<"[redacted]">> end, Headers),
    NoSecretInExport andalso NoSecretInTrace andalso RedactedPresent.

%% A metric name over 128 bytes is refused at the API edge and never lands
%% in the registry.
metrics_name_bound_probe() ->
    ok = gleamunison_metrics_sup:ensure_started(),
    Long = binary:copy(<<"x">>, 200),
    nil = gleamunison_metrics:counter(Long, 1),
    Entries = gleamunison_metrics:list_metrics(),
    not lists:any(
        fun({{counter, N}, _}) -> N =:= Long; (_) -> false end, Entries).

%% Budget registry snapshot as JSON, for asserting metering from Gleam.
llm_budget_snapshot_json() ->
    iolist_to_binary(json:encode(gleamunison_llm_budget:snapshot())).

set_env(Key, Value) when is_binary(Key), is_binary(Value) ->
    true = os:putenv(binary_to_list(Key), binary_to_list(Value)),
    nil.

unset_env(Key) when is_binary(Key) ->
    true = os:unsetenv(binary_to_list(Key)),
    nil.
