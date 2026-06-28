-module(gleamunison_adapters).
-export([register/3, find/2, adapt/2]).

-define(TABLE, gleamunison_adapters).

ensure_table() ->
    case ets:whereis(?TABLE) of
        undefined -> ets:new(?TABLE, [set, public, named_table]);
        _ -> ok
    end.

register(OldHash, NewHash, Fun) when is_binary(OldHash), is_binary(NewHash), is_function(Fun, 1) ->
    ensure_table(),
    ets:insert(?TABLE, {{OldHash, NewHash}, Fun}),
    ok.

find(OldHash, NewHash) when is_binary(OldHash), is_binary(NewHash) ->
    ensure_table(),
    case ets:lookup(?TABLE, {OldHash, NewHash}) of
        [{_, Fun}] -> {ok, Fun};
        [] -> {error, no_adapter}
    end.

adapt(OldHash, NewHash) when is_binary(OldHash), is_binary(NewHash) ->
    case find(OldHash, NewHash) of
        {ok, _Fun} -> {ok, adapted};
        {error, _} -> {error, no_adapter}
    end.
