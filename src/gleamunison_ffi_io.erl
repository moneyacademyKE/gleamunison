-module(gleamunison_ffi_io).
-export([
    state_get/1, state_set/2,
    eval_expression/1,
    spawn_concurrent_evals/0,
    sync_connect/1, sync_send_refs/2, sync_receive_diff/1,
    sync_request_defs/2, sync_push_defs/2,
    serialize_term/1, deserialize_term/1,
    register_peer_refs/2, compute_diff/1, fetch_defs_binary/1, receive_pushed_defs/1
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

%% --- Sync stubs (peer networking) ---

node_atom(NodeBin) ->
    list_to_atom(binary_to_list(NodeBin)).

is_real_node(NodeBin) ->
    binary:match(NodeBin, <<"@">>) =/= nomatch.

sync_connect(NodeBin) ->
    case is_real_node(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case net_adm:ping(NodeAtom) of
                pong -> {ok, nil};
                pang -> {error, <<"Connection failed (pang)">>}
            end;
        false ->
            {ok, nil}
    end.

sync_send_refs(NodeBin, Refs) ->
    case is_real_node(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, register_peer_refs, [node(), Refs]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            {ok, nil}
    end.

sync_receive_diff(NodeBin) ->
    case is_real_node(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, compute_diff, [node()]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            case NodeBin of
                <<"test_node">> -> {ok, [<<"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20">>]};
                _ -> {ok, []}
            end
    end.

sync_request_defs(NodeBin, Refs) ->
    case is_real_node(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, fetch_defs_binary, [Refs]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            case NodeBin of
                <<"test_node">> -> {ok, [{<<"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20">>, <<"dummy_blob">>}]};
                _ -> {ok, []}
            end
    end.

sync_push_defs(NodeBin, Defs) ->
    case is_real_node(NodeBin) of
        true ->
            NodeAtom = node_atom(NodeBin),
            case rpc:call(NodeAtom, gleamunison_ffi_io, receive_pushed_defs, [Defs]) of
                {badrpc, Reason} -> {error, list_to_binary(io_lib:format("RPC failed: ~p", [Reason]))};
                Res -> {ok, Res}
            end;
        false ->
            {ok, nil}
    end.

register_peer_refs(PeerNode, Refs) ->
    try ets:whereis(gleamunison_peer_refs) of
        undefined ->
            ets:new(gleamunison_peer_refs, [set, public, named_table]);
        _ ->
            ok
    catch _:_ ->
        ets:new(gleamunison_peer_refs, [set, public, named_table])
    end,
    ets:insert(gleamunison_peer_refs, {PeerNode, Refs}),
    ok.

compute_diff(PeerNode) ->
    PeerRefs = case catch ets:lookup(gleamunison_peer_refs, PeerNode) of
        [{PeerNode, R}] -> R;
        _ -> []
    end,
    PeerRefsSet = sets:from_list(PeerRefs),
    LocalRefs = get_local_refs_hex(),
    [R || R <- LocalRefs, not sets:is_element(R, PeerRefsSet)].

fetch_defs_binary(Refs) ->
    case persistent_term:get({gleamunison, active_storage}, undefined) of
        undefined -> [];
        {Type, Tab} ->
            Lookup = fun(Hex) ->
                Ref = hex_to_ref(Hex),
                case Type of
                    ets -> gleamunison_storage:lookup(Tab, Ref);
                    dets -> gleamunison_storage:dets_lookup(Tab, Ref);
                    partitioned_dets -> gleamunison_storage:partitioned_dets_lookup(Tab, Ref);
                    mnesia -> gleamunison_storage:mnesia_lookup(Tab, Ref)
                end
            end,
            lists:filter_map(fun(Hex) ->
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
                Ref = hex_to_ref(Hex),
                case Type of
                    ets -> gleamunison_storage:insert(Tab, Ref, Bytes);
                    dets -> gleamunison_storage:dets_insert(Tab, Ref, Bytes);
                    partitioned_dets -> gleamunison_storage:partitioned_dets_insert(Tab, Ref, Bytes);
                    mnesia -> gleamunison_storage:mnesia_insert(Tab, Ref, Bytes)
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
    iolist_to_binary(gleamunison_ffi:hash_to_hex(Bytes)).

hex_to_ref(Hex) ->
    Bytes = gleamunison_ffi:hex_to_bytes(Hex),
    {ref, {hash, Bytes}}.

serialize_term(Term) ->
    erlang:term_to_binary(Term).

deserialize_term(Bytes) when is_binary(Bytes) ->
    erlang:binary_to_term(Bytes).
