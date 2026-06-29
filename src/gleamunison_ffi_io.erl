-module(gleamunison_ffi_io).
-export([
    state_get/1, state_set/2,
    eval_expression/1,
    spawn_concurrent_evals/0,
    sync_connect/1, sync_send_refs/2, sync_receive_diff/1,
    sync_request_defs/2, sync_push_defs/2,
    serialize_term/1, deserialize_term/1,
    register_peer_refs/2, compute_diff/1, fetch_defs_binary/1, receive_pushed_defs/1,
    node_atom/1, hex_to_ref/1, ref_to_hex/1
]).

%% --- State (process dictionary) ---

state_get(Key) when is_binary(Key) ->
    case erlang:get(Key) of
        undefined -> {ok, null};
        Val -> {ok, Val}
    end.

state_set(Key, Val) when is_binary(Key) ->
    erlang:put(Key, Val),
    {ok, ok}.

%% --- Expression evaluation ---

eval_expression(Expr) when is_binary(Expr) ->
    try
        case gleamunison@parser:parse_string(Expr) of
            {ok, _STerm} ->
                case gleamunison@repl:eval_string_unique(Expr) of
                    {ok, Result} -> {ok, Result};
                    {error, E} -> {error, E}
                end;
            {error, ParseReason} ->
                {error, iolist_to_binary(io_lib:format("~tp", [ParseReason]))}
        end
    catch
        Class:Reason:Stack ->
            {error, iolist_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stack]))}
    end.

%% --- Concurrent evaluation test ---

spawn_concurrent_evals() ->
    Parent = self(),
    Pids = [spawn(fun() ->
        {ok, R} = gleamunison@repl:eval_string_unique(<<"42">>),
        Parent ! {done, R}
    end) || _ <- lists:seq(1, 10)],
    [receive {done, <<"42 : ", _/binary>>} -> ok after 5000 -> error(timeout) end || _ <- Pids],
    ok.

%% --- Sync protocol (peer networking) ---

node_atom(NodeBin) ->
    list_to_atom(binary_to_list(NodeBin)).

has_node_at(Name) ->
    binary:match(Name, <<"@">>) =/= nomatch.

parse_host_port(Name) ->
    NameStr = binary_to_list(Name),
    case string:rchr(NameStr, $:) of
        0 -> {Name, gleamunison_tcp_sync:get_port()};
        I ->
            Host = list_to_binary(string:substr(NameStr, 1, I - 1)),
            Port = list_to_integer(string:substr(NameStr, I + 1)),
            {Host, Port}
    end.

tcp_call(PeerName, Message) ->
    {Host, Port} = parse_host_port(PeerName),
    Annotated = {self_name(), Message},
    case gleamunison_tcp_sync:send_message({Host, Port}, Annotated) of
        {ok, ok} -> {ok, nil};
        {ok, {ok, Data}} -> {ok, Data};
        {ok, {error, Reason}} -> {error, Reason};
        {error, Reason} -> {error, list_to_binary(io_lib:format("TCP: ~p", [Reason]))}
    end.

self_name() ->
    list_to_binary(atom_to_list(node())).

sync_connect(NodeBin) ->
    case has_node_at(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case net_adm:ping(NodeAtom) of
                pong -> {ok, nil};
                pang -> {error, <<"Connection failed (pang)">>}
            end;
        false ->
            tcp_call(NodeBin, {connect, node()})
    end.

sync_send_refs(NodeBin, Refs) ->
    case has_node_at(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, register_peer_refs, [node(), Refs]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            tcp_call(NodeBin, {send_refs, Refs})
    end.

sync_receive_diff(NodeBin) ->
    case has_node_at(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, compute_diff, [node()]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            tcp_call(NodeBin, {receive_diff, []})
    end.

sync_request_defs(NodeBin, Refs) ->
    case has_node_at(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, fetch_defs_binary, [Refs]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            tcp_call(NodeBin, {request_defs, Refs})
    end.

sync_push_defs(NodeBin, Defs) ->
    case has_node_at(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, receive_pushed_defs, [Defs]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            tcp_call(NodeBin, {push_defs, Defs})
    end.

register_peer_refs(Peer, Refs) ->
    ensure_table(gleamunison_peer_refs),
    ets:insert(gleamunison_peer_refs, {Peer, Refs}),
    ok.

ensure_table(Name) ->
    case ets:whereis(Name) of
        undefined -> ets:new(Name, [set, public, named_table]);
        _ -> ok
    end.

compute_diff(Peer) ->
    ensure_table(gleamunison_peer_refs),
    PeerRefs = try ets:lookup(gleamunison_peer_refs, Peer) of
        [{Peer, R}] -> R;
        _ -> []
    catch
        _:_ -> []
    end,
    PeerRefsSet = sets:from_list(PeerRefs),
    LocalRefs = get_local_refs_hex(),
    [R || R <- LocalRefs, not sets:is_element(R, PeerRefsSet)].

fetch_defs_binary(Refs) ->
    case persistent_term:get({gleamunison, active_storage}, undefined) of
        undefined -> [];
        {Type, Tab} ->
            Lookup = fun(Hex) ->
                Key = gleamunison_ffi:hex_to_bytes(Hex),
                case Type of
                    ets -> gleamunison_storage:lookup(Tab, Key);
                    dets -> gleamunison_storage:dets_lookup(Tab, Key);
                    partitioned_dets -> gleamunison_storage:partitioned_dets_lookup(Tab, Key);
                    mnesia -> gleamunison_storage:mnesia_lookup(Tab, Key)
                end
            end,
            lists:filtermap(fun(Hex) ->
                case Lookup(Hex) of
                    {ok, {some, Bytes}} -> {true, {Hex, Bytes}};
                    _ -> false
                end
            end, Refs)
    end.

receive_pushed_defs(Defs) ->
    case persistent_term:get({gleamunison, active_storage}, undefined) of
        undefined -> ok;
        {Type, Tab} ->
            Insert = fun(Hex, Bytes) ->
                Key = gleamunison_ffi:hex_to_bytes(Hex),
                case Type of
                    ets -> gleamunison_storage:insert(Tab, Key, Bytes);
                    dets -> gleamunison_storage:dets_insert(Tab, Key, Bytes);
                    partitioned_dets -> gleamunison_storage:partitioned_dets_insert(Tab, Key, Bytes);
                    mnesia -> gleamunison_storage:mnesia_insert(Tab, Key, Bytes)
                end
            end,
            lists:foreach(fun({Hex, Bytes}) ->
                Insert(Hex, Bytes)
            end, Defs),
            ok
    end.

get_local_refs_hex() ->
    case persistent_term:get({gleamunison, active_storage}, undefined) of
        undefined -> [];
        {Type, Tab} ->
            RefsResult = case Type of
                ets -> gleamunison_storage:list_refs(Tab);
                dets -> gleamunison_storage:dets_list_refs(Tab);
                partitioned_dets -> gleamunison_storage:partitioned_dets_list_refs(Tab);
                mnesia -> gleamunison_storage:mnesia_list_refs(Tab)
            end,
            case RefsResult of
                {ok, Refs} -> [ref_to_hex(R) || R <- Refs];
                _ -> []
            end
    end.

ref_to_hex({ref, {hash, Bytes}}) ->
    iolist_to_binary(gleamunison_ffi:hash_to_hex(Bytes));
ref_to_hex(Bytes) when is_binary(Bytes) ->
    iolist_to_binary(gleamunison_ffi:hash_to_hex(Bytes)).

hex_to_ref(Hex) ->
    Bytes = gleamunison_ffi:hex_to_bytes(Hex),
    {ref, {hash, Bytes}}.

serialize_term(Term) ->
    erlang:term_to_binary(Term).

deserialize_term(Bytes) when is_binary(Bytes) ->
    erlang:binary_to_term(Bytes).
