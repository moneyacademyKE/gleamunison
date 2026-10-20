-module(gleamunison_trace).
-export([start_trace/0, capture_request/3, list_traces/0, get_trace/1,
         clear_traces/0, trace_count/0]).

-define(TRACE_TABLE, gleamunison_traces).
%% The trace table is a bounded cache, not a record: at most MAX_TRACES
%% entries, oldest evicted first. Anything that must survive belongs in the
%% evidence store, not here.
-define(MAX_TRACES, 512).

start_trace() -> ensure_table().

capture_request(Method, Path, Headers) when is_binary(Method), is_binary(Path), is_list(Headers) ->
    ensure_table(),
    Seq = erlang:unique_integer([positive, monotonic]),
    Id = integer_to_binary(Seq),
    TS = calendar:system_time_to_rfc3339(erlang:system_time(millisecond), [{unit, millisecond}, {offset, "Z"}]),
    BinTS = list_to_binary(TS),
    %% Headers are redacted at capture time: the redaction boundary is the
    %% write, so no reader (route, export, SSE) can ever leak a credential.
    Entry = {BinTS, Id, Method, Path, redact_headers(Headers)},
    ets:insert(?TRACE_TABLE, {Seq, Entry}),
    evict_oldest(),
    notify_sse_trace(Id, Method, Path),
    {ok, Id}.

ensure_table() ->
    case ets:whereis(?TRACE_TABLE) of
        undefined ->
            ets:new(?TRACE_TABLE, [ordered_set, public, named_table]);
        _ -> ok
    end.

trace_count() ->
    ensure_table(),
    ets:info(?TRACE_TABLE, size).

list_traces() ->
    ensure_table(),
    All = ets:tab2list(?TRACE_TABLE),
    Sorted = lists:reverse(lists:sort([E || {_, E} <- All])),
    lists:sublist(Sorted, 50).

get_trace(Id) when is_binary(Id) ->
    ensure_table(),
    Entries = [E || {_, E} <- ets:tab2list(?TRACE_TABLE)],
    case lists:keyfind(Id, 2, Entries) of
        {_, _, _, _, _} = Entry -> {ok, Entry};
        false -> {error, <<"not found">>}
    end.

clear_traces() ->
    case ets:whereis(?TRACE_TABLE) of
        undefined -> ok;
        _ -> ets:delete(?TRACE_TABLE)
    end.

%% The table is an ordered_set keyed on a monotonic integer, so ets:first
%% is always the oldest surviving entry.
evict_oldest() ->
    case ets:info(?TRACE_TABLE, size) of
        N when N > ?MAX_TRACES ->
            ets:delete(?TRACE_TABLE, ets:first(?TRACE_TABLE)),
            evict_oldest();
        _ -> ok
    end.

redact_headers(Headers) ->
    [{header_key(K), redact_value(K, V)} || {K, V} <- Headers].

redact_value(K, V) ->
    case lists:member(header_key(K), sensitive_headers()) of
        true -> <<"[redacted]">>;
        false -> V
    end.

header_key(K) when is_binary(K) ->
    list_to_binary(string:lowercase(binary_to_list(K)));
header_key(K) when is_atom(K) ->
    header_key(atom_to_binary(K, utf8));
header_key(K) when is_list(K) ->
    header_key(list_to_binary(K)).

sensitive_headers() ->
    [<<"authorization">>, <<"cookie">>, <<"set-cookie">>,
     <<"x-api-key">>, <<"proxy-authorization">>, <<"x-sync-token">>].

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
