-module(gleamunison_tcp_sync).
-behaviour(gen_server).

-export([start_link/0, stop/0, get_port/0, send_message/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 9876).

-record(state, {lsock, port}).

%% --- Public API ---

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
            Bin = term_to_binary(Message),
            ok = gen_tcp:send(Sock, <<(byte_size(Bin)):32, Bin/binary>>),
            Result = case gen_tcp:recv(Sock, 4, 5000) of
                {ok, <<Len:32>>} when Len =< 1048576 ->
                    case gen_tcp:recv(Sock, Len, 5000) of
                        {ok, ReplyBin} -> safe_decode(ReplyBin);
                        {error, Reason} -> {error, {recv_body, Reason}}
                    end;
                {ok, <<_Len:32>>} -> {error, message_too_large};
                {error, Reason} -> {error, {recv_length, Reason}}
            end,
            gen_tcp:close(Sock),
            Result;
        {error, Reason} ->
            {error, {connect, Reason}}
    end.

%% --- gen_server callbacks ---

init([]) ->
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

%% --- Acceptor ---

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

%% --- Connection handler ---

handle_connection(Sock) ->
    case gen_tcp:recv(Sock, 4, 30000) of
        {ok, <<Len:32>>} when Len =< 1048576 ->
            case gen_tcp:recv(Sock, Len, 30000) of
                {ok, Bin} ->
                    Reply = case safe_decode(Bin) of
                        {ok, Request} -> dispatch(Request);
                        {error, Reason} -> {error, Reason}
                    end,
                    ReplyBin = term_to_binary(Reply),
                    gen_tcp:send(Sock, <<(byte_size(ReplyBin)):32, ReplyBin/binary>>);
                {error, _} ->
                    ok
            end;
        {ok, <<_Len:32>>} ->
            ReplyBin = term_to_binary({error, <<"message too large">>}),
            gen_tcp:send(Sock, <<(byte_size(ReplyBin)):32, ReplyBin/binary>>);
        {error, _} ->
            ok
    end,
    gen_tcp:close(Sock).

%% --- Dispatch ---

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
    gleamunison_ffi_io:receive_pushed_defs(Defs),
    ok;

dispatch(_Unknown) ->
    {error, <<"unknown message type">>}.

safe_decode(Bin) ->
    try {ok, binary_to_term(Bin, [safe])}
    catch _:_ -> {error, <<"invalid message">>}
    end.
