-module(gleamunison_storage).
-export([new/0, insert/3, lookup/2, list_refs/1]).

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
