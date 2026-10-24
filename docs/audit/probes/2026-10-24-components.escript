#!/usr/bin/env escript
%%! -noshell
%% Audit-only probe. Run from repo root after the normal build:
%%   escript docs/audit/probes/2026-10-24-components.escript
%% No source mutation, network call, production store, or disk-backed fixture.
%% All generated data lives inside this VM. Timings are synthetic, not SLAs.

main(["benchmark"]) ->
    ok = code:add_paths(filelib:wildcard("build/dev/erlang/*/ebin")),
    benchmark_search(),
    benchmark_store(),
    io:format("benchmark_probe=PASS~n");
main(_) ->
    Paths = filelib:wildcard("build/dev/erlang/*/ebin"),
    true = code:add_paths(Paths) =:= ok,
    io:format("otp=~s architecture=~s~n",
              [erlang:system_info(otp_release),
               erlang:system_info(system_architecture)]),
    probe_failures(),
    probe_framing(),
    probe_mnesia_delete(),
    benchmark_search(),
    benchmark_store(),
    probe_depth(),
    io:format("audit_probe=PASS (defects reproduced, not fixed)~n").

emit(Name, Value) -> io:format("~s=~tp~n", [Name, Value]).

probe_failures() ->
    Error = {error, {storage_error, <<"audit_disk_failed">>}},
    Adapter = {storage_adapter,
               fun(_, _) -> {ok, nil} end,
               fun(_) -> Error end,
               fun(_) -> {ok, nil} end,
               fun() -> Error end,
               fun() -> {ok, nil} end},
    Ref = gleamunison@repl_eval:ref_for_name(<<"audit_target">>),
    Dependents = gleamunison@store_deps:dependents_on_branch(
                   Adapter, <<"main">>, Ref),
    [] = Dependents,
    emit("dependents_after_storage_error", Dependents),
    Aliases = gleamunison@store_deps:other_names_on_branch(
                Adapter, <<"main">>, Ref, <<"name">>),
    [] = Aliases,
    emit("aliases_after_storage_error", Aliases).

probe_framing() ->
    Body = <<"caf", 195, 169>>,
    5 = byte_size(Body),
    Encoded = gleamunison@lsp:encode_frame(Body),
    <<"Content-Length: 4\r\n\r\n", _/binary>> = Encoded,
    emit("lsp_utf8_body_bytes", byte_size(Body)),
    emit("lsp_utf8_declared_length", 4),
    Proper = <<"Content-Length: 5\r\n\r\n", Body/binary>>,
    {error, nil} = gleamunison@lsp:decode_framed(Proper),
    emit("lsp_proper_utf8_frame_decode", {error, nil}),
    {ok, {<<"cafe">>, <<>>}} = gleamunison@lsp:decode_framed(
                                 <<"Content-Length: 4\r\n\r\ncafe">>),
    emit("lsp_ascii_control", ok).

probe_mnesia_delete() ->
    {ok, _} = application:ensure_all_started(mnesia),
    Tab = gleamunison_audit_delete,
    {atomic, ok} = mnesia:create_table(
                    Tab, [{attributes, [key, val]},
                          {ram_copies, [node()]}]),
    ok = mnesia:wait_for_tables([Tab], 5000),
    {ok, nil} = gleamunison_storage:mnesia_insert(
                  Tab, <<"key">>, <<"payload">>),
    {ok, nil} = gleamunison_storage:mnesia_delete(Tab, <<"key">>),
    After = gleamunison_storage:mnesia_lookup(Tab, <<"key">>),
    {ok, {some, <<"payload">>}} = After,
    emit("mnesia_delete_return", {ok, nil}),
    emit("mnesia_lookup_after_delete", After).

measure(Label, N, Work) ->
    _ = Work(),
    Times = [begin {Us, _} = timer:tc(Work), Us end
             || _ <- lists:seq(1, 3)],
    Median = lists:nth(2, lists:sort(Times)),
    io:format("~s n=~B times_us=~w median_us=~B~n",
              [Label, N, Times, Median]).

benchmark_search() ->
    lists:foreach(fun(N) ->
        Docs = [{doc, I, [<<"retry">>, <<"network">>, <<"timeout">>,
                          <<"backoff">>]} || I <- lists:seq(1, N)],
        Texts = [{doc_v, I, <<"retry network timeout backoff">>}
                 || I <- lists:seq(1, N)],
        measure("rank_bm25", N, fun() ->
            gleamunison@rank:rank(<<"retry timeout">>, Docs)
        end),
        measure("rank_hybrid", N, fun() ->
            gleamunison@rank:rank_hybrid(<<"retry timeout">>, Texts)
        end)
    end, [100, 500, 1000]).

benchmark_store() ->
    lists:foreach(fun(N) ->
        CB = gleamunison@codebase:empty(),
        lists:foreach(fun(I) ->
            Def = {term_def, {int, I}, {builtin, int_type}},
            Ref = {ref, gleamunison@codebase:hash_of_definition(Def)},
            {ok, _} = gleamunison@codebase:insert(
                        CB, {unit, Ref, [{Ref, Def}]})
        end, lists:seq(1, N)),
        Adapter = gleamunison@codebase:get_adapter(CB),
        Target = gleamunison@repl_eval:ref_for_name(<<"audit_missing">>),
        measure("dependents_ets", N, fun() ->
            gleamunison@store_deps:dependents(Adapter, Target)
        end),
        measure("evidence_ets", N, fun() ->
            gleamunison@evidence:for_subject(Adapter, <<"audit_missing">>)
        end)
    end, [100, 1000, 5000]).

probe_depth() ->
    lists:foreach(fun(N) ->
        Source = iolist_to_binary([lists:duplicate(N, <<"(lam x ">>),
                                   <<"1">>, lists:duplicate(N, <<")">>)]),
        {ok, _} = gleamunison@parser:parse_string(Source),
        io:format("accepted_parser_depth=~B source_bytes=~B~n",
                  [N, byte_size(Source)])
    end, [100, 1000, 5000]).
