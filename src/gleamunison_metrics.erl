-module(gleamunison_metrics).
-export([counter/2, gauge/2, histogram/2, list_metrics/0]).

-define(TABLE, gleamunison_metrics).

ensure_table() ->
    case ets:whereis(?TABLE) of
        undefined -> ets:new(?TABLE, [set, public, named_table]);
        _ -> ok
    end.

counter(Name, Delta) when is_binary(Name), is_integer(Delta) ->
    ensure_table(),
    case ets:lookup(?TABLE, {counter, Name}) of
        [{_, Val}] -> ets:insert(?TABLE, {{counter, Name}, Val + Delta});
        [] -> ets:insert(?TABLE, {{counter, Name}, Delta})
    end,
    try telemetry:execute([gleamunison, counter, Delta], #{name => Name, delta => Delta})
    catch _:_ -> ok end.

gauge(Name, Value) when is_binary(Name), is_number(Value) ->
    ensure_table(),
    ets:insert(?TABLE, {{gauge, Name}, Value}),
    try telemetry:execute([gleamunison, gauge, Name], #{name => Name, value => Value})
    catch _:_ -> ok end.

histogram(Name, Value) when is_binary(Name), is_number(Value) ->
    ensure_table(),
    Key = {histogram, Name, erlang:unique_integer()},
    ets:insert(?TABLE, {Key, Value}),
    try telemetry:execute([gleamunison, histogram, Name], #{name => Name, value => Value})
    catch _:_ -> ok end.

list_metrics() ->
    ensure_table(),
    ets:tab2list(?TABLE).
