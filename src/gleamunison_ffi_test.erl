-module(gleamunison_ffi_test).
-export([test_storage_owner_survives/0, test_effects_runtime/0, test_ffi_io_coverage/0]).

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
