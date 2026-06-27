-module(gleamunison_ffi_io).
-export([
    state_get/1, state_set/2,
    eval_expression/1,
    spawn_concurrent_evals/0,
    sync_connect/1, sync_send_refs/2, sync_receive_diff/1,
    sync_request_defs/2, sync_push_defs/2
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
            {error, Reason} ->
                {error, iolist_to_binary(io_lib:format("~tp", [Reason]))}
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

sync_connect(<<"test_node">>) -> {ok, nil};
sync_connect(_Node) -> {ok, nil}.

sync_send_refs(<<"test_node">>, _Refs) -> {ok, nil};
sync_send_refs(_Node, _Refs) -> {ok, nil}.

sync_receive_diff(<<"test_node">>) ->
    {ok, [<<"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20">>]};
sync_receive_diff(_Node) -> {ok, []}.

sync_request_defs(<<"test_node">>,
    [<<"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20">>]) ->
    {ok, [{<<"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20">>, <<"dummy_blob">>}]};
sync_request_defs(_Node, _Refs) -> {ok, []}.

sync_push_defs(<<"test_node">>, _Defs) -> {ok, nil};
sync_push_defs(_Node, _Defs) -> {ok, nil}.
