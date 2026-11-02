-module(gleamunison_tables).
-export([ensure/2]).

%% One owner for the "ensure this named ETS table exists" idiom (bk-09d9).
%% Five sites previously hand-rolled it with two divergent shapes: a
%% whereis-only check (race-prone — a table created between the check and
%% the new crashes the creator with badarg) and a try/catch-only create
%% (race-safe but silent about existence). This combines both: whereis
%% first, and the create wrapped in catch so a concurrent creator can
%% never crash the caller.
%%
%% Table names and options are load-bearing: log/trace tables are
%% ordered_set (range scans for evict_oldest), the rest are set; all are
%% public+named_table so the dev server, the escript, and tests all
%% address them by atom. Each caller pins its own exact name+options.
%% Returns ok once the table exists (ets:new's atom return is an
%% implementation detail no caller needs).
ensure(Name, Opts) when is_atom(Name), is_list(Opts) ->
    case ets:whereis(Name) of
        undefined ->
            try ets:new(Name, Opts) of _ -> ok catch _:_ -> ok end;
        _ ->
            ok
    end.
