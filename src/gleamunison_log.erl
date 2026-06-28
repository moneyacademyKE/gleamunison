-module(gleamunison_log).
-export([log_entry/4]).

-define(ETS_TABLE, gleamunison_logs).

log_entry(Level, Message, Keys, Vals) when is_binary(Level), is_binary(Message) ->
    ensure_table(),
    TS = calendar:system_time_to_rfc3339(erlang:system_time(millisecond), [{unit, millisecond}, {offset, "Z"}]),
    Context = maps:from_list(lists:zip(Keys, Vals)),
    Entry = {list_to_binary(TS), Level, Message, Context},
    ets:insert(?ETS_TABLE, Entry),
    io:format("[~s] ~s: ~s~n", [Level, TS, Message]).

ensure_table() ->
    case ets:whereis(?ETS_TABLE) of
        undefined ->
            ets:new(?ETS_TABLE, [ordered_set, public, named_table]),
            ets:insert(?ETS_TABLE, {erlang:unique_integer()});
        _ -> ok
    end.
