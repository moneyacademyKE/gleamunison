-module(gleamunison_observability).
-export([export/0, export_json/0, saturation/0]).

%% Redaction is by construction: this module never reads raw trace headers,
%% never touches env vars or key material, and only emits counts, names, and
%% bounded recent summaries. The redaction boundary for headers is the write
%% (gleamunison_trace redacts at capture); here we omit them entirely.

export() ->
    #{exported_at => timestamp(),
      metrics => metrics_snapshot(),
      traces => traces_snapshot(),
      logs => logs_snapshot(),
      saturation => saturation(),
      readiness => gleamunison_readiness:report()}.

export_json() ->
    iolist_to_binary(json:encode(export())).

timestamp() ->
    list_to_binary(calendar:system_time_to_rfc3339(
        erlang:system_time(millisecond), [{unit, millisecond}, {offset, "Z"}])).

metrics_snapshot() ->
    Entries = case catch gleamunison_metrics:list_metrics() of
        L when is_list(L) -> L;
        _ -> []
    end,
    Acc = lists:foldl(fun fold_metric/2, {#{}, #{}, #{}}, Entries),
    {Counters, Gauges, Histograms} = Acc,
    #{counters => Counters, gauges => Gauges,
      histograms => maps:map(fun finalize_histogram/2, Histograms)}.

fold_metric({{counter, Name}, Value}, {C, G, H}) ->
    {C#{Name => Value}, G, H};
fold_metric({{gauge, Name}, Value}, {C, G, H}) ->
    {C, G#{Name => Value}, H};
fold_metric({{histogram, Name, _Slot}, Value}, {C, G, H}) ->
    Entry = maps:get(Name, H, {0, infinity, 0}),
    {Count, Min, Max} = Entry,
    {C, G, H#{Name => {Count + 1, min_num(Min, Value), max_num(Max, Value)}}};
fold_metric(_, Acc) ->
    Acc.

finalize_histogram(_Name, {Count, Min, Max}) ->
    #{count => Count, min => Min, max => Max}.

min_num(infinity, V) -> V;
min_num(A, B) when is_number(A), is_number(B) -> erlang:min(A, B).

max_num(A, B) when is_number(A), is_number(B) -> erlang:max(A, B).

traces_snapshot() ->
    Recent = [trace_summary(E) || E <- gleamunison_trace:list_traces()],
    #{count => gleamunison_trace:trace_count(), limit => 512, recent => Recent}.

trace_summary({TS, Id, Method, Path, _Headers}) ->
    #{id => Id, timestamp => TS, method => Method, path => Path}.

logs_snapshot() ->
    Entries = case ets:whereis(gleamunison_logs) of
        undefined -> [];
        _ -> ets:tab2list(gleamunison_logs)
    end,
    Sorted = lists:reverse(lists:sort(Entries)),
    Recent = lists:sublist(Sorted, 50),
    #{count => ets_size(gleamunison_logs), limit => 1024,
      recent => [log_summary(E) || E <- Recent]}.

log_summary({_Seq, TS, Level, Message, _Context}) ->
    #{timestamp => TS, level => Level, message => Message};
log_summary(_) ->
    #{timestamp => <<>>, level => <<"unknown">>, message => <<>>}.

%% One place that knows every runtime bound. Readiness and /api/status both
%% read this so the limits cannot drift apart from the probes.
saturation() ->
    #{http_workers => http_worker_count(),
      http_worker_limit => 64,
      mcp_active => mcp_active_count(),
      mcp_request_limit => 64,
      sse_clients => ets_size(gleamunison_sse_clients),
      sse_client_limit => 32,
      trace_entries => gleamunison_trace:trace_count(),
      trace_entry_limit => 512,
      log_entries => ets_size(gleamunison_logs),
      log_entry_limit => 1024}.

http_worker_count() ->
    case persistent_term:get({gleamunison_http, listener}, undefined) of
        {Pid, _Socket} when is_pid(Pid) ->
            case catch gleamunison_http:worker_count(Pid) of
                N when is_integer(N) -> N;
                _ -> 0
            end;
        _ -> 0
    end.

mcp_active_count() ->
    case whereis(gleamunison_mcp_session) of
        undefined -> 0;
        Pid ->
            case catch sys:get_state(Pid, 200) of
                #{active := N} when is_integer(N) -> N;
                _ -> 0
            end
    end.

ets_size(Name) ->
    case ets:whereis(Name) of
        undefined -> 0;
        _ -> ets:info(Name, size)
    end.
