-module(gleamunison_storage).
-export([
    new/0, insert/3, lookup/2, list_refs/1,
    dets_new/1, dets_insert/3, dets_lookup/2, dets_list_refs/1, dets_close/1,
    dets_delete_file/1,
    partitioned_dets_new/1, partitioned_dets_insert/3, partitioned_dets_lookup/2,
    partitioned_dets_list_refs/1, partitioned_dets_close/1, partitioned_dets_delete_file/1,
    mnesia_new/1, mnesia_insert/3, mnesia_lookup/2, mnesia_list_refs/1, mnesia_close/1,
    test_make_ref/1, get_open_dets_count/1
]).

new() ->
    P = self(), R = make_ref(),
    spawn(fun() -> T = ets:new(gleamunison_store, [set, public]), P ! {R, T}, receive after infinity -> ok end end),
    receive {R, T} -> T after 5000 -> error(timeout) end.

insert(Tab, Ref, Bytes) -> ets:insert(Tab, {Ref, Bytes}), {ok, nil}.

lookup(Tab, Ref) ->
    case ets:lookup(Tab, Ref) of
        [{Ref, B}] -> {ok, {some, B}};
        [] -> {ok, none}
    end.

list_refs(Tab) -> {ok, [R || {R, _} <- ets:tab2list(Tab)]}.

err(R) -> {error, {storage_error, list_to_binary(io_lib:format("~p", [R]))}}.

dets_new(Path) ->
    N = erlang:binary_to_atom(<<"gleamunison_dets_", Path/binary>>, utf8),
    case dets:open_file(N, [{file, binary_to_list(Path)}, {type, set}]) of
        {ok, N} -> {ok, N};
        {error, R} -> err(R)
    end.

dets_insert(Tab, Ref, Bytes) ->
    case dets:insert(Tab, {Ref, Bytes}) of ok -> {ok, nil}; {error, R} -> err(R) end.

dets_lookup(Tab, Ref) ->
    case dets:lookup(Tab, Ref) of
        [{Ref, B}] -> {ok, {some, B}};
        [] -> {ok, none};
        {error, R} -> err(R)
    end.

dets_list_refs(Tab) ->
    case dets:select(Tab, [{{'$1', '_'}, [], ['$1']}]) of {error, R} -> err(R); L -> {ok, L} end.

dets_close(Tab) ->
    case dets:close(Tab) of ok -> {ok, nil}; {error, R} -> err(R) end.

dets_delete_file(Path) ->
    case file:delete(Path) of ok -> {ok, nil}; {error, R} -> err(R) end.

partitioned_dets_new(DP) ->
    Dir = case binary:last(DP) of $/ -> DP; _ -> <<DP/binary, "/">> end,
    ok = filelib:ensure_dir(filename:join(binary_to_list(Dir), "x")), {ok, Dir}.

ensure_dets_open(Dir, P) ->
    Key = {gleamunison_open_dets, Dir},
    Open = case erlang:get(Key) of undefined -> []; L -> L end,
    Tab = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, P>>, utf8),
    case lists:member(P, Open) of
        true -> erlang:put(Key, [P | lists:delete(P, Open)]), Tab;
        false ->
            NewOpen = case length(Open) >= 4 of
                true ->
                    LRU = lists:last(Open),
                    dets:close(erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, LRU>>, utf8)),
                    [P | lists:droplast(Open)];
                false -> [P | Open]
            end,
            erlang:put(Key, NewOpen),
            {ok, Tab} = dets:open_file(Tab, [{file, binary_to_list(<<Dir/binary, P, ".dets">>)}, {type, set}]),
            Tab
    end.

partitioned_dets_insert(Dir, Ref, Bytes) ->
    <<N:4, _/bitstring>> = Ref, dets_insert(ensure_dets_open(Dir, hex(N)), Ref, Bytes).

partitioned_dets_lookup(Dir, Ref) ->
    <<N:4, _/bitstring>> = Ref, dets_lookup(ensure_dets_open(Dir, hex(N)), Ref).

partitioned_dets_list_refs(Dir) ->
    R = [case filelib:is_file(binary_to_list(<<Dir/binary, P, ".dets">>)) of
        false -> {ok, []};
        true -> dets_list_refs(ensure_dets_open(Dir, P))
    end || P <- "0123456789abcdef"],
    case lists:keyfind(error, 1, R) of
        false -> {ok, lists:append([L || {ok, L} <- R])};
        Err -> Err
    end.

partitioned_dets_close(Dir) ->
    K = {gleamunison_open_dets, Dir},
    case erlang:get(K) of
        undefined -> ok;
        L ->
            [dets:close(erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, P>>, utf8)) || P <- L],
            erlang:erase(K)
    end,
    {ok, nil}.

partitioned_dets_delete_file(DP) ->
    Dir = case binary:last(DP) of $/ -> DP; _ -> <<DP/binary, "/">> end,
    partitioned_dets_close(Dir),
    [file:delete(<<Dir/binary, P, ".dets">>) || P <- "0123456789abcdef"], {ok, nil}.

test_make_ref(Bytes) -> {ref, {hash, Bytes}}.

get_open_dets_count(DP) ->
    Dir = case binary:last(DP) of $/ -> DP; _ -> <<DP/binary, "/">> end,
    case erlang:get({gleamunison_open_dets, Dir}) of undefined -> 0; L -> length(L) end.

hex(N) -> case N < 10 of true -> $0 + N; false -> $a + N - 10 end.

mnesia_new(TabName) ->
    case mnesia:start() of
        ok ->
            N = erlang:binary_to_atom(<<"gleamunison_mnesia_", TabName/binary>>, utf8),
            case mnesia:create_table(N, [{attributes, [key, val]}, {type, set}]) of
                {atomic, ok} ->
                    ok = mnesia:wait_for_tables([N], 5000),
                    {ok, N};
                {aborted, {already_exists, N}} ->
                    ok = mnesia:wait_for_tables([N], 5000),
                    {ok, N};
                {aborted, R} -> err(R)
            end;
        {error, R} -> err(R)
    end.

mnesia_insert(Tab, Ref, Bytes) ->
    F = fun() -> mnesia:write({Tab, Ref, Bytes}) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, nil};
        {aborted, R} -> err(R)
    end.

mnesia_lookup(Tab, Ref) ->
    F = fun() -> mnesia:read(Tab, Ref) end,
    case mnesia:transaction(F) of
        {atomic, [{Tab, Ref, Bytes}]} -> {ok, {some, Bytes}};
        {atomic, []} -> {ok, none};
        {aborted, R} -> err(R)
    end.

mnesia_list_refs(Tab) ->
    F = fun() -> mnesia:all_keys(Tab) end,
    case mnesia:transaction(F) of
        {atomic, Keys} -> {ok, Keys};
        {aborted, R} -> err(R)
    end.

mnesia_close(_Tab) -> {ok, nil}.

