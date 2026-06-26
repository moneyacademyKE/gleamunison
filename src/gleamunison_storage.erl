-module(gleamunison_storage).
-export([new/0, insert/3, lookup/2, list_refs/1]).

new() ->
    ets:new(gleamunison_store, [set, public]).

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
