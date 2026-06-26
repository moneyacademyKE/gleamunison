-module(gleamunison_storage).
-export([
    new/0, insert/3, lookup/2, list_refs/1,
    dets_new/1, dets_insert/3, dets_lookup/2, dets_list_refs/1, dets_close/1,
    dets_delete_file/1
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

holder_loop(Tab) ->
    receive
        _ -> holder_loop(Tab)
    end.

insert(Tab, Ref, Bytes) when is_binary(Ref), is_binary(Bytes) ->
    ets:insert(Tab, {Ref, Bytes}),
    {ok, nil}.

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
