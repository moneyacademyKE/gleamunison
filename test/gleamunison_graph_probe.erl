-module(gleamunison_graph_probe).
-export([index_eval_calls/1]).

%% Run graph queries in one traced process. Trace only the caller-side index
%% boundary: evaluator workers install their own tracer and must not be touched.
index_eval_calls(Fun) when is_function(Fun, 0) ->
    {module, _} = code:ensure_loaded('gleamunison@codebase_index'),
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Parent ! {self(), ready},
        receive run -> Parent ! {self(), done, Fun()} end
    end),
    1 = erlang:trace_pattern({'gleamunison@codebase_index', eval_index_source, 1}, true, [local]),
    receive {Pid, ready} -> ok after 1000 -> error(graph_probe_not_ready) end,
    1 = erlang:trace(Pid, true, [call, {tracer, Parent}]),
    Pid ! run,
    try await_result(Pid, Monitor, 0)
    after
        erlang:trace_pattern({'gleamunison@codebase_index', eval_index_source, 1}, false, [local]),
        erlang:demonitor(Monitor, [flush]),
        exit(Pid, kill)
    end.

await_result(Pid, Monitor, Count) ->
    receive
        {trace, Pid, call, {'gleamunison@codebase_index', eval_index_source, _}} ->
            await_result(Pid, Monitor, Count + 1);
        {Pid, done, Result} ->
            {Result, drain_traces(Pid, Count)};
        {'DOWN', Monitor, process, Pid, Reason} ->
            error({graph_probe_failed, Reason})
    after 5000 ->
        error(graph_probe_timeout)
    end.

drain_traces(Pid, Count) ->
    receive
        {trace, Pid, call, {'gleamunison@codebase_index', eval_index_source, _}} ->
            drain_traces(Pid, Count + 1)
    after 0 -> Count
    end.
