-module(gleamunison_coverage_runner).
-export([main/0, main/1]).

main() -> main([]).
main(_) ->
    cover:start(),
    Modules = ['gleamunison_sup', 'gleamunison@elab_ctx', 'gleamunison@log', 'gleamunison_crypto', 'gleamunison@loader', 'gleamunison@elab_term', 'gleamunison@http_client', 'gleamunison@codebase', 'gleamunison@identity', 'gleamunison@elab_pat', 'gleamunison@infer_helper', 'gleamunison_ffi', 'gleamunison@@main', 'gleamunison@type_pretty', 'gleamunison@pipeline', 'gleamunison_log', 'gleamunison@parser', 'gleamunison_json', 'gleamunison@lower', 'gleamunison@compile', 'gleamunison@elab_def', 'gleamunison_health', 'gleamunison_property', 'gleamunison_config', 'gleamunison@elab_types', 'gleamunison@json', 'gleamunison_tcp_sync', 'gleamunison_adapters', 'gleamunison@storage', 'gleamunison_effets', 'gleamunison_storage', 'gleamunison@repl', 'gleamunison_http', 'gleamunison@datetime', 'gleamunison@typecheck', 'gleamunison', 'gleamunison_template', 'gleamunison@lexer', 'gleamunison_http_util', 'gleamunison@types', 'gleamunison_datetime', 'gleamunison@metrics', 'gleamunison_metrics', 'gleamunison@template', 'gleamunison@sync', 'gleamunison_repl_ffi', 'gleamunison@ast', 'gleamunison_trace', 'gleamunison@http', 'gleamunison@repl_io', 'gleamunison@crypto', 'gleamunison@config', 'gleamunison@inference', 'gleamunison@repl_eval', 'gleamunison_http_client', 'gleamunison@health', 'gleamunison@sync_types', 'gleamunison_ffi_io', 'gleamunison@jets', 'gleamunison_http_routes', 'gleamunison_jets', 'gleamunison@filepath', 'gleamunison@effects', 'gleamunison@elaborate'],
    lists:foreach(fun(M) ->
        case cover:compile_beam(code:which(M)) of
            {ok, _} -> ok;
            Err -> io:format("Failed to instrument ~p: ~p~n", [M, Err])
        end
    end, Modules),
    io:format("=== Running Tests ===~n"),
    TestBeams = filelib:wildcard("build/dev/erlang/gleamunison/ebin/*_test.beam"),
    TestModules = [list_to_atom(filename:basename(B, ".beam")) || B <- TestBeams],
    io:format("Running ~p unit tests...~n", [length(TestModules)]),
    eunit:test(TestModules),
    Levels = dogfood:all_levels(),
    lists:foreach(fun(N) ->
        Key = list_to_binary("level" ++ integer_to_list(N)),
        case gleam@dict:get(Levels, Key) of
            {ok, Fun} -> Fun();
            _ -> ok
        end
    end, lists:seq(1, 1250)),
    io:format("=== Analyzing Coverage ===~n"),
    Results = lists:map(fun(M) ->
        case cover:analyze(M, coverage, module) of
            {ok, {M, {Cov, NotCov}}} -> {M, Cov, NotCov};
            Other -> io:format("M: ~p, result: ~p~n", [M, Other]), {M, 0, 0}
        end
    end, Modules),
    io:format("~-35s ~-10s ~-10s ~-10s~n", ["Module", "Covered", "Uncovered", "%"]),
    io:format("~70c~n", [$-]),
    {TotalCov, TotalNotCov} = lists:foldl(fun({M, Cov, NotCov}, {AccCov, AccNotCov}) ->
        Total = Cov + NotCov,
        Pct = case Total of 0 -> 100.0; _ -> (Cov * 100.0) / Total end,
        io:format("~-35s ~-10w ~-10w ~-10.1f%~n", [M, Cov, NotCov, Pct]),
        if NotCov > 0 ->
            {ok, Lines} = cover:analyze(M, coverage, line),
            UncoveredLines = [L || {{_, L}, {0, 1}} <- Lines],
            io:format("  Uncovered lines: ~w~n", [lists:sort(UncoveredLines)]);
           true -> ok
        end,
        {AccCov + Cov, AccNotCov + NotCov}
    end, {0, 0}, Results),
    io:format("~70c~n", [$=]),
    GrandTotal = TotalCov + TotalNotCov,
    GrandPct = case GrandTotal of 0 -> 100.0; _ -> (TotalCov * 100.0) / GrandTotal end,
    io:format("~-35s ~-10w ~-10w ~-10.1f%~n", ["TOTAL", TotalCov, TotalNotCov, GrandPct]),
    if TotalNotCov > 0 ->
        io:format("~nCoverage is less than 100%!~n"),
        init:stop(1);
       true ->
        io:format("~n100% Code Coverage Achieved!~n"),
        init:stop(0)
    end.
