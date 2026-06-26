-module(gleamunison_storage).
-export([
    new/0, insert/3, lookup/2, list_refs/1,
    dets_new/1, dets_insert/3, dets_lookup/2, dets_list_refs/1, dets_close/1,
    dets_delete_file/1,
    partitioned_dets_new/1, partitioned_dets_insert/3, partitioned_dets_lookup/2,
    partitioned_dets_list_refs/1, partitioned_dets_close/1, partitioned_dets_delete_file/1
]).

new() ->
    Parent = self(),
    Ref = make_ref(),
    spawn(fun() ->
        Tab = ets:new(gleamunison_store, [set, public]),
        Parent ! {Ref, Tab},
        holder_loop(Tab)
    end),
    receive
        {Ref, Tab} -> Tab
    after 5000 ->
        error(ets_creation_timeout)
    end.

holder_loop(Tab) -> receive _ -> holder_loop(Tab) end.

insert(Tab, Ref, Bytes) when is_binary(Ref), is_binary(Bytes) ->
    ets:insert(Tab, {Ref, Bytes}), {ok, nil}.

lookup(Tab, Ref) when is_binary(Ref) ->
    case ets:lookup(Tab, Ref) of
        [{Ref, Bytes}] -> {ok, {some, Bytes}};
        [] -> {ok, none}
    end.

list_refs(Tab) ->
    {ok, [Ref || {Ref, _} <- ets:tab2list(Tab)]}.

dets_new(Path) when is_binary(Path) ->
    Name = erlang:binary_to_atom(<<"gleamunison_dets_", Path/binary>>, utf8),
    case dets:open_file(Name, [{file, binary_to_list(Path)}, {type, set}]) of
        {ok, Name} -> {ok, Name};
        {error, Reason} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [Reason]))}}
    end.

dets_insert(Tab, Ref, Bytes) when is_binary(Ref), is_binary(Bytes) ->
    case dets:insert(Tab, {Ref, Bytes}) of
        ok -> {ok, nil};
        {error, Reason} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [Reason]))}}
    end.

dets_lookup(Tab, Ref) when is_binary(Ref) ->
    case dets:lookup(Tab, Ref) of
        {error, Reason} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [Reason]))}};
        [{Ref, Bytes}] -> {ok, {some, Bytes}};
        [] -> {ok, none}
    end.

dets_list_refs(Tab) ->
    case dets:select(Tab, [{{'$1', '_'}, [], ['$1']}]) of
        {error, Reason} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [Reason]))}};
        List -> {ok, List}
    end.

dets_close(Tab) ->
    case dets:close(Tab) of
        ok -> {ok, nil};
        {error, Reason} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [Reason]))}}
    end.

dets_delete_file(Path) when is_binary(Path) ->
    case file:delete(Path) of
        ok -> {ok, nil};
        {error, Reason} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [Reason]))}}
    end.

partitioned_dets_new(DirPath) when is_binary(DirPath) ->
    Dir = case binary:last(DirPath) of $/ -> DirPath; _ -> <<DirPath/binary, "/">> end,
    ok = filelib:ensure_dir(filename:join(binary_to_list(Dir), "dummy")),
    OpenRes = [dets_open_partition(Dir, P) || P <- "0123456789abcdef"],
    case lists:filter(fun({error, _}) -> true; (_) -> false end, OpenRes) of
        [] -> {ok, Dir};
        [Error | _] -> Error
    end.

dets_open_partition(Dir, PrefixChar) ->
    Name = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, PrefixChar>>, utf8),
    FilePath = binary_to_list(<<Dir/binary, PrefixChar, ".dets">>),
    case dets:open_file(Name, [{file, FilePath}, {type, set}]) of
        {ok, Name} -> ok;
        {error, R} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [R]))}}
    end.

partitioned_dets_insert(Dir, Ref, Bytes) when is_binary(Dir), is_binary(Ref), is_binary(Bytes) ->
    <<N:4, _/bitstring>> = Ref,
    Tab = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, (hex(N))>>, utf8),
    case dets:insert(Tab, {Ref, Bytes}) of
        ok -> {ok, nil};
        {error, R} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [R]))}}
    end.

partitioned_dets_lookup(Dir, Ref) when is_binary(Dir), is_binary(Ref) ->
    <<N:4, _/bitstring>> = Ref,
    Tab = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, (hex(N))>>, utf8),
    case dets:lookup(Tab, Ref) of
        {error, R} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [R]))}};
        [{Ref, Bytes}] -> {ok, {some, Bytes}};
        [] -> {ok, none}
    end.

partitioned_dets_list_refs(Dir) ->
    Results = [dets_list_partition_refs(Dir, P) || P <- "0123456789abcdef"],
    case lists:filter(fun({error, _}) -> true; (_) -> false end, Results) of
        [] -> 
            AllRefs = lists:foldl(fun({ok, L}, Acc) -> L ++ Acc end, [], Results),
            {ok, AllRefs};
        [Error | _] -> Error
    end.

dets_list_partition_refs(Dir, PrefixChar) ->
    Tab = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, PrefixChar>>, utf8),
    case dets:select(Tab, [{{'$1', '_'}, [], ['$1']}]) of
        {error, R} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [R]))}};
        List -> {ok, List}
    end.

partitioned_dets_close(Dir) ->
    Results = [dets_close_partition(Dir, P) || P <- "0123456789abcdef"],
    case lists:filter(fun({error, _}) -> true; (_) -> false end, Results) of
        [] -> {ok, nil};
        [Error | _] -> Error
    end.

dets_close_partition(Dir, PrefixChar) ->
    Tab = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, PrefixChar>>, utf8),
    case dets:close(Tab) of
        ok -> ok;
        {error, R} -> {error, {storage_error, list_to_binary(io_lib:format("~p", [R]))}}
    end.

partitioned_dets_delete_file(DirPath) ->
    Dir = case binary:last(DirPath) of $/ -> DirPath; _ -> <<DirPath/binary, "/">> end,
    [file:delete(<<Dir/binary, P, ".dets">>) || P <- "0123456789abcdef"],
    {ok, nil}.

hex(N) when N < 10 -> $0 + N;
hex(N) -> $a + N - 10.
