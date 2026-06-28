-module(gleamunison_datetime).
-export([now/0, now_iso8601/0, format_iso8601/1, from_iso8601/1, add_seconds/2, diff_seconds/2]).

now() ->
    erlang:system_time(second).

now_iso8601() ->
    list_to_binary(calendar:system_time_to_rfc3339(erlang:system_time(second), [{offset, "Z"}])).

format_iso8601(Timestamp) when is_integer(Timestamp) ->
    list_to_binary(calendar:system_time_to_rfc3339(Timestamp, [{unit, second}, {offset, "Z"}])).

from_iso8601(IsoString) when is_binary(IsoString) ->
    try calendar:rfc3339_to_system_time(binary_to_list(IsoString), [{unit, second}]) of
        TS -> {ok, TS}
    catch _:_ -> {error, <<"invalid ISO 8601">>}
    end.

add_seconds(Timestamp, N) when is_integer(Timestamp), is_integer(N) ->
    Timestamp + N.

diff_seconds(T1, T2) when is_integer(T1), is_integer(T2) ->
    T1 - T2.
