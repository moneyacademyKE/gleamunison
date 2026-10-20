-module(gleamunison_log).
-export([log_entry/4, log_count/0, clear_logs/0]).

-define(ETS_TABLE, gleamunison_logs).
%% Bounded cache, same contract as traces: at most MAX_LOG_ENTRIES,
%% oldest evicted first. The durable record is whatever drains this buffer.
-define(MAX_LOG_ENTRIES, 1024).

log_entry(Level, Message, Keys, Vals) when is_binary(Level), is_binary(Message) ->
    ensure_table(),
    %% Keyed on a monotonic integer, not the timestamp: two entries in the
    %% same millisecond must both survive, and ets:first is the oldest.
    Seq = erlang:unique_integer([positive, monotonic]),
    TS = calendar:system_time_to_rfc3339(erlang:system_time(millisecond), [{unit, millisecond}, {offset, "Z"}]),
    Context = maps:from_list(lists:zip(Keys, Vals)),
    Entry = {Seq, list_to_binary(TS), Level, Message, Context},
    ets:insert(?ETS_TABLE, Entry),
    evict_oldest(),
    io:format("[~s] ~s: ~s~n", [Level, TS, Message]).

log_count() ->
    ensure_table(),
    ets:info(?ETS_TABLE, size).

clear_logs() ->
    case ets:whereis(?ETS_TABLE) of
        undefined -> ok;
        _ -> ets:delete(?ETS_TABLE)
    end.

evict_oldest() ->
    case ets:info(?ETS_TABLE, size) of
        N when N > ?MAX_LOG_ENTRIES ->
            ets:delete(?ETS_TABLE, ets:first(?ETS_TABLE)),
            evict_oldest();
        _ -> ok
    end.

ensure_table() ->
    case ets:whereis(?ETS_TABLE) of
        undefined ->
            ets:new(?ETS_TABLE, [ordered_set, public, named_table]);
        _ -> ok
    end.
