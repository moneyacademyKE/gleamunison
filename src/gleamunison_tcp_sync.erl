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
            Bin = term_to_binary(outgoing_message(Message)),
            Result = case byte_size(Bin) =< ?MAX_FRAME_BYTES of
                false -> {error, message_too_large};
                true ->
                    ok = gen_tcp:send(Sock, <<(byte_size(Bin)):32, Bin/binary>>),
                    receive_reply(Sock)
            end,
            gen_tcp:close(Sock),
            Result;
        {error, Reason} ->
            {error, {connect, Reason}}
    end.

outgoing_message(Message) ->
    case os:getenv("GLEAMUNISON_SYNC_TOKEN") of
        false -> Message;
        "" -> Message;
        Token -> {auth, list_to_binary(Token), Message}
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
    case gen_tcp:recv(Sock, 4, 30000) of
        {ok, <<Len:32>>} when Len =< ?MAX_FRAME_BYTES ->
            case gen_tcp:recv(Sock, Len, 30000) of
                {ok, Bin} ->
                    Reply = case safe_decode(Bin) of
                        {ok, Request} -> authenticated_dispatch(Request);
                        {error, Reason} -> {error, Reason}
                    end,
                    send_reply(Sock, Reply);
                {error, _} ->
                    ok
            end;
        {ok, <<_Len:32>>} ->
            send_reply(Sock, {error, message_too_large});
        {error, _} ->
            ok
    end,
    gen_tcp:close(Sock).

send_reply(Sock, Reply) ->
    ReplyBin = term_to_binary(Reply),
    gen_tcp:send(Sock, <<(byte_size(ReplyBin)):32, ReplyBin/binary>>).

authenticated_dispatch({auth, Token, Request}) when is_binary(Token) ->
    case configured_token() of
        {ok, Expected} ->
            case constant_time_equal(Expected, Token) of
                true -> dispatch(Request);
                false -> {error, auth_failed}
            end;
        none ->
            {error, auth_not_configured}
    end;
authenticated_dispatch(Request) ->
    case configured_token() of
        {ok, _Expected} -> {error, auth_required};
        none -> dispatch(Request)
    end.

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
