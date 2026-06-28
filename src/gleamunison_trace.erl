-module(gleamunison_trace).
-export([start_trace/0, capture_request/3, list_traces/0, get_trace/1, clear_traces/0]).

-define(TRACE_TABLE, gleamunison_traces).

start_trace() ->
    case ets:whereis(?TRACE_TABLE) of
        undefined ->
            ets:new(?TRACE_TABLE, [ordered_set, public, named_table]);
        _ -> ok
    end.

capture_request(Method, Path, Headers) when is_binary(Method), is_binary(Path), is_list(Headers) ->
    ensure_table(),
    Id = integer_to_binary(erlang:unique_integer([positive])),
    TS = calendar:system_time_to_rfc3339(erlang:system_time(millisecond), [{unit, millisecond}, {offset, "Z"}]),
    BinTS = list_to_binary(TS),
    Entry = {BinTS, Id, Method, Path, Headers},
    ets:insert(?TRACE_TABLE, {Id, Entry}),
    notify_sse_trace(Id, Method, Path),
    {ok, Id}.

ensure_table() ->
    case ets:whereis(?TRACE_TABLE) of
        undefined ->
            ets:new(?TRACE_TABLE, [ordered_set, public, named_table]);
        _ -> ok
    end.

list_traces() ->
    ensure_table(),
    All = ets:tab2list(?TRACE_TABLE),
    Sorted = lists:reverse(lists:sort([E || {_, E} <- All])),
    lists:sublist(Sorted, 50).

get_trace(Id) when is_binary(Id) ->
    ensure_table(),
    case ets:lookup(?TRACE_TABLE, Id) of
        [{_, Entry}] -> {ok, Entry};
        [] -> {error, <<"not found">>}
    end.

clear_traces() ->
    case ets:whereis(?TRACE_TABLE) of
        undefined -> ok;
        _ -> ets:delete(?TRACE_TABLE)
    end.

notify_sse_trace(Id, Method, Path) ->
    case ets:whereis(gleamunison_sse_clients) of
        undefined -> ok;
        _ ->
            Payload = iolist_to_binary(io_lib:format(
                "{\"id\":\"~s\",\"method\":\"~s\",\"path\":\"~s\"}",
                [Id, Method, Path])),
            Clients = ets:match(gleamunison_sse_clients, {'$1', true}),
            [Pid ! {sse_event, <<"trace">>, Payload} || [Pid] <- Clients],
            ok
    end.
