-module(gleamunison_tcp_sync).
-behaviour(gen_server).

-export([start_link/0, stop/0, get_port/0, send_message/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 9876).
-define(MAX_FRAME_BYTES, 1048576).

-record(state, {lsock, port}).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:call(?SERVER, stop).

get_port() ->
    persistent_term:get({?MODULE, port}, ?DEFAULT_PORT).

send_message({Host, Port}, Message) when is_list(Host); is_binary(Host) ->
    HostStr = case is_binary(Host) of true -> binary_to_list(Host); false -> Host end,
    case gen_tcp:connect(HostStr, Port, [binary, {packet, 0}, {active, false}], 5000) of
        {ok, Sock} ->
            Result = handshake_and_send(Sock, Message),
            gen_tcp:close(Sock),
            Result;
        {error, Reason} ->
            {error, {connect, Reason}}
    end.

%% Protocol v2: hello → challenge → HMAC proof → message. The token never
%% crosses the wire; the proof binds client nonce + server nonce + message
%% digest, so a captured frame cannot be replayed to another session or with
%% another payload. Without a configured token (loopback local profile) the
%% legacy single-frame path is preserved.
handshake_and_send(Sock, Message) ->
    case configured_token() of
        none -> send_frame(Sock, Message), receive_reply(Sock);
        {ok, Token} ->
            ClientNonce = crypto:strong_rand_bytes(16),
            send_frame(Sock, {hello, ClientNonce}),
            case receive_reply(Sock) of
                {ok, {challenge, ServerNonce}} when is_binary(ServerNonce) ->
                    Digest = crypto:hash(sha256, term_to_binary(Message)),
                    Proof = crypto:mac(hmac, sha256, Token,
                                       <<ClientNonce/binary, ServerNonce/binary, Digest/binary>>),
                    send_frame(Sock, {auth2, ClientNonce, Proof, Message}),
                    receive_reply(Sock);
                {error, _} = Error -> Error;
                _Other -> {error, handshake_failed}
            end
    end.

send_frame(Sock, Term) ->
    Bin = term_to_binary(Term),
    case byte_size(Bin) =< ?MAX_FRAME_BYTES of
        false -> oversized;
        true -> gen_tcp:send(Sock, <<(byte_size(Bin)):32, Bin/binary>>)
    end.

receive_reply(Sock) ->
    case gen_tcp:recv(Sock, 4, 5000) of
        {ok, <<Len:32>>} when Len =< ?MAX_FRAME_BYTES ->
            case gen_tcp:recv(Sock, Len, 5000) of
                {ok, ReplyBin} -> safe_decode(ReplyBin);
                {error, Reason} -> {error, {recv_body, Reason}}
            end;
        {ok, <<_Len:32>>} -> {error, message_too_large};
        {error, Reason} -> {error, {recv_length, Reason}}
    end.

init([]) ->
    application:ensure_all_started(crypto),
    {ok, LSock} = gen_tcp:listen(0, [binary, {packet, 0}, {active, false},
                                      {reuseaddr, true}, {backlog, 32},
                                      {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(LSock),
    persistent_term:put({?MODULE, port}, Port),
    spawn_link(fun() -> acceptor(LSock) end),
    {ok, #state{lsock = LSock, port = Port}}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(readiness, _From, #state{lsock = Socket} = State) ->
    Ready = case inet:sockname(Socket) of {ok, _} -> true; _ -> false end,
    {reply, Ready, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{lsock = LSock}) ->
    gen_tcp:close(LSock),
    persistent_term:erase({?MODULE, port}),
    ok.

acceptor(LSock) ->
    case gen_tcp:accept(LSock, 5000) of
        {ok, Sock} ->
            spawn(fun() -> handle_connection(Sock) end),
            acceptor(LSock);
        {error, closed} ->
            ok;
        {error, timeout} ->
            acceptor(LSock);
        {error, _Reason} ->
            acceptor(LSock)
    end.

handle_connection(Sock) ->
    case configured_token() of
        none -> handle_legacy_frame(Sock);
        {ok, Token} -> handle_handshake(Sock, Token)
    end,
    gen_tcp:close(Sock).

handle_legacy_frame(Sock) ->
    case recv_frame(Sock) of
        {ok, Request} -> send_reply(Sock, dispatch(Request));
        {error, Reason} -> send_reply(Sock, {error, Reason})
    end.

%% v2 server side: issue a per-connection nonce, then accept exactly one
%% proof. Replay is rejected because the (client, server) nonce pair is
%% single-use and the server nonce is fresh per connection.
handle_handshake(Sock, Token) ->
    case recv_frame(Sock) of
        {ok, {hello, ClientNonce}} when is_binary(ClientNonce), byte_size(ClientNonce) =< 64 ->
            ServerNonce = crypto:strong_rand_bytes(16),
            send_reply(Sock, {challenge, ServerNonce}),
            case recv_frame(Sock) of
                {ok, {auth2, ClientNonce, Proof, Message}} when is_binary(Proof) ->
                    Digest = crypto:hash(sha256, term_to_binary(Message)),
                    Expected = crypto:mac(hmac, sha256, Token,
                                          <<ClientNonce/binary, ServerNonce/binary, Digest/binary>>),
                    case constant_time_equal(Expected, Proof) of
                        false -> send_reply(Sock, {error, auth_failed});
                        true ->
                            case claim_session(ClientNonce, ServerNonce) of
                                ok -> send_reply(Sock, dispatch(Message));
                                replay -> send_reply(Sock, {error, auth_replay})
                            end
                    end;
                {ok, _} -> send_reply(Sock, {error, auth_required});
                {error, Reason} -> send_reply(Sock, {error, Reason})
            end;
        {ok, {auth, _, _}} -> send_reply(Sock, {error, legacy_auth_rejected});
        {ok, _} -> send_reply(Sock, {error, auth_required});
        {error, Reason} -> send_reply(Sock, {error, Reason})
    end.

recv_frame(Sock) ->
    case gen_tcp:recv(Sock, 4, 30000) of
        {ok, <<Len:32>>} when Len =< ?MAX_FRAME_BYTES ->
            case gen_tcp:recv(Sock, Len, 30000) of
                {ok, Bin} -> safe_decode(Bin);
                {error, Reason} -> {error, Reason}
            end;
        {ok, <<_Len:32>>} -> {error, message_too_large};
        {error, Reason} -> {error, Reason}
    end.

claim_session(ClientNonce, ServerNonce) ->
    ensure_session_table(),
    Key = crypto:hash(sha256, <<ClientNonce/binary, ServerNonce/binary>>),
    case ets:insert_new(gleamunison_sync_sessions, {Key}) of
        true -> ok;
        false -> replay
    end.

ensure_session_table() ->
    case ets:whereis(gleamunison_sync_sessions) of
        undefined ->
            try ets:new(gleamunison_sync_sessions, [set, public, named_table])
            catch _:_ -> gleamunison_sync_sessions end;
        _ -> gleamunison_sync_sessions
    end.

send_reply(Sock, Reply) ->
    ReplyBin = term_to_binary(Reply),
    gen_tcp:send(Sock, <<(byte_size(ReplyBin)):32, ReplyBin/binary>>).

configured_token() ->
    case os:getenv("GLEAMUNISON_SYNC_TOKEN") of
        false -> none;
        "" -> none;
        Token -> {ok, list_to_binary(Token)}
    end.

constant_time_equal(Expected, Provided) when is_binary(Expected), is_binary(Provided) ->
    constant_time_hash_compare(crypto:hash(sha256, Expected), crypto:hash(sha256, Provided), 0).

constant_time_hash_compare(<<A, RestA/binary>>, <<B, RestB/binary>>, Acc) ->
    constant_time_hash_compare(RestA, RestB, Acc bor (A bxor B));
constant_time_hash_compare(<<>>, <<>>, Acc) -> Acc =:= 0.

dispatch({SelfName, {connect, _Name}}) when is_binary(SelfName) ->
    gleamunison_ffi_io:register_peer_refs(SelfName, []),
    ok;

dispatch({SelfName, {send_refs, Refs}}) when is_binary(SelfName), is_list(Refs) ->
    gleamunison_ffi_io:register_peer_refs(SelfName, Refs),
    ok;

dispatch({SelfName, {receive_diff, _Refs}}) when is_binary(SelfName) ->
    Diff = gleamunison_ffi_io:compute_diff(SelfName),
    {ok, Diff};

dispatch({_SelfName, {request_defs, Refs}}) when is_list(Refs) ->
    Defs = gleamunison_ffi_io:fetch_defs_binary(Refs),
    {ok, Defs};

dispatch({_SelfName, {push_defs, Defs}}) when is_list(Defs) ->
    gleamunison_ffi_io:receive_pushed_defs(Defs);

dispatch(_Unknown) ->
    {error, <<"unknown message type">>}.

safe_decode(<<131, 80, _/binary>>) ->
    {error, <<"invalid message">>};
safe_decode(Bin) ->
    try
        {Term, Used} = binary_to_term(Bin, [safe, used]),
        true = Used =:= byte_size(Bin),
        {ok, Term}
    catch _:_ -> {error, <<"invalid message">>}
    end.
