-module(gleamunison_ffi_io).
-export([
    state_get/1, state_set/2,
    eval_expression/1,
    spawn_concurrent_evals/0,
    sync_connect/1, sync_send_refs/2, sync_receive_diff/1,
    sync_request_defs/2, sync_push_defs/2,
    serialize_term/1, deserialize_term/1,
    register_peer_refs/2, compute_diff/1, fetch_defs_binary/1, receive_pushed_defs/1,
    node_atom/1, hex_to_ref/1, ref_to_hex/1, parse_host_port/1
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
    case valid_node_name(NodeBin) of
        true -> list_to_atom(binary_to_list(NodeBin));
        false -> error({invalid_node_name, NodeBin})
    end.

valid_node_name(NodeBin) when is_binary(NodeBin), byte_size(NodeBin) =< 255 ->
    has_node_at(NodeBin) andalso valid_node_chars(NodeBin);
valid_node_name(_) -> false.

valid_node_chars(<<>>) -> true;
valid_node_chars(<<C, Rest/binary>>) when C >= $a, C =< $z -> valid_node_chars(Rest);
valid_node_chars(<<C, Rest/binary>>) when C >= $A, C =< $Z -> valid_node_chars(Rest);
valid_node_chars(<<C, Rest/binary>>) when C >= $0, C =< $9 -> valid_node_chars(Rest);
valid_node_chars(<<$., Rest/binary>>) -> valid_node_chars(Rest);
valid_node_chars(<<$-, Rest/binary>>) -> valid_node_chars(Rest);
valid_node_chars(<<$_, Rest/binary>>) -> valid_node_chars(Rest);
valid_node_chars(<<$@, Rest/binary>>) -> valid_node_chars(Rest);
valid_node_chars(<<$:, Rest/binary>>) -> valid_node_chars(Rest);
valid_node_chars(_) -> false.

has_node_at(Name) ->
    binary:match(Name, <<"@">>) =/= nomatch.

parse_host_port(Name) ->
    gleamunison_peer:parse(Name).

tcp_call(PeerName, Message) ->
    case parse_host_port(PeerName) of
        {error, _} = Error -> Error;
        {ok, {Host, Port}} ->
            Annotated = {self_name(), Message},
            case gleamunison_tcp_sync:send_message({Host, Port}, Annotated) of
                {ok, ok} -> {ok, nil};
                {ok, {ok, Data}} -> {ok, Data};
                {ok, {error, Reason}} -> {error, Reason};
                {error, Reason} -> {error, list_to_binary(io_lib:format("TCP: ~p", [Reason]))}
            end
    end.

self_name() ->
    list_to_binary(atom_to_list(node())).

sync_connect(NodeBin) ->
    case has_node_at(NodeBin) of
        true ->
            case safe_node_atom(NodeBin) of
                {ok, NodeAtom} ->
                    case net_adm:ping(NodeAtom) of
                        pong -> {ok, nil};
                        pang -> {error, <<"Connection failed (pang)">>}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        false ->
            tcp_call(NodeBin, {connect, node()})
    end.

sync_send_refs(NodeBin, Refs) ->
    case has_node_at(NodeBin) of
        true ->
            case safe_node_atom(NodeBin) of
                {ok, NodeAtom} ->
                    case rpc:call(NodeAtom, gleamunison_ffi_io, register_peer_refs, [node(), Refs]) of
                        {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                        Res -> {ok, Res}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        false ->
            tcp_call(NodeBin, {send_refs, Refs})
    end.

sync_receive_diff(NodeBin) ->
    case has_node_at(NodeBin) of
        true ->
            case safe_node_atom(NodeBin) of
                {ok, NodeAtom} ->
                    case rpc:call(NodeAtom, gleamunison_ffi_io, compute_diff, [node()]) of
                        {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                        Res -> {ok, Res}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        false ->
            tcp_call(NodeBin, {receive_diff, []})
    end.

sync_request_defs(NodeBin, Refs) ->
    case has_node_at(NodeBin) of
        true ->
            case safe_node_atom(NodeBin) of
                {ok, NodeAtom} ->
                    case rpc:call(NodeAtom, gleamunison_ffi_io, fetch_defs_binary, [Refs]) of
                        {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                        Res -> {ok, Res}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        false ->
            tcp_call(NodeBin, {request_defs, Refs})
    end.

sync_push_defs(NodeBin, Defs) ->
    case has_node_at(NodeBin) of
        true ->
            case safe_node_atom(NodeBin) of
                {ok, NodeAtom} ->
                    case rpc:call(NodeAtom, gleamunison_ffi_io, receive_pushed_defs, [Defs]) of
                        {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                        {error, _} = Error -> Error;
                        ok -> {ok, nil}
                    end;
                {error, Reason} -> {error, Reason}
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
                case hex_to_ref(Hex) of
                    {ok, {ref, {hash, Key}}} -> storage_lookup(Type, Tab, Key);
                    {error, _} = Error -> Error
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
    case gleamunison_cas:verify_batch(Defs) of
        {error, _} = Error -> Error;
        {ok, Verified} ->
            case persistent_term:get({gleamunison, active_storage}, undefined) of
                undefined -> {error, <<"storage_unavailable">>};
                {Type, Tab} ->
                    case preflight_defs(Type, Tab, Verified) of
                        ok -> insert_defs(Type, Tab, Verified);
                        {error, _} = Error -> Error
                    end
            end
    end.

preflight_defs(_Type, _Tab, []) -> ok;
preflight_defs(Type, Tab, [{Ref, Bytes} | Rest]) ->
    case storage_lookup(Type, Tab, Ref) of
        {ok, none} -> preflight_defs(Type, Tab, Rest);
        {ok, {some, Bytes}} -> preflight_defs(Type, Tab, Rest);
        {ok, {some, _Other}} -> {error, <<"content_conflict">>};
        {error, Reason} -> storage_failure(Reason)
    end.

insert_defs(_Type, _Tab, []) -> ok;
insert_defs(Type, Tab, [{Ref, Bytes} | Rest]) ->
    Result = case Type of
        ets -> gleamunison_storage:insert(Tab, Ref, Bytes);
        dets -> gleamunison_storage:dets_insert(Tab, Ref, Bytes);
        partitioned_dets -> gleamunison_storage:partitioned_dets_insert(Tab, Ref, Bytes);
        mnesia -> gleamunison_storage:mnesia_insert(Tab, Ref, Bytes)
    end,
    case Result of
        {ok, nil} -> insert_defs(Type, Tab, Rest);
        {error, Reason} -> storage_failure(Reason)
    end.

storage_lookup(ets, Tab, Ref) -> gleamunison_storage:lookup(Tab, Ref);
storage_lookup(dets, Tab, Ref) -> gleamunison_storage:dets_lookup(Tab, Ref);
storage_lookup(partitioned_dets, Tab, Ref) -> gleamunison_storage:partitioned_dets_lookup(Tab, Ref);
storage_lookup(mnesia, Tab, Ref) -> gleamunison_storage:mnesia_lookup(Tab, Ref).

storage_failure(Reason) ->
    {error, iolist_to_binary(io_lib:format("storage failure: ~p", [Reason]))}.

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
    gleamunison@identity:parse_ref_hex(Hex).

serialize_term(Term) ->
    erlang:term_to_binary(Term).

deserialize_term(Bytes) when is_binary(Bytes) ->
    erlang:binary_to_term(Bytes, [safe]).

safe_node_atom(NodeBin) ->
    try {ok, node_atom(NodeBin)}
    catch _:_ -> {error, <<"Invalid node name">>}
    end.
