-module(tables_boundary_ffi).
-export([double_ensure_ok/0, concurrent_ensure_ok/0, options_preserved/0]).

%% bk-09d9: the shared ensure/2 must be idempotent, race-safe under
%% concurrent creators, and must preserve the caller's exact options.
-define(TEST_TABLE, gleamunison_tables_test_t).
-define(TEST_TABLE_2, gleamunison_tables_test_u).

cleanup(Name) ->
    case ets:whereis(Name) of
        undefined -> ok;
        _ -> ets:delete(Name)
    end.

double_ensure_ok() ->
    cleanup(?TEST_TABLE),
    ok = gleamunison_tables:ensure(?TEST_TABLE, [set, public, named_table]),
    ok = gleamunison_tables:ensure(?TEST_TABLE, [set, public, named_table]),
    Result = undefined =/= ets:whereis(?TEST_TABLE),
    cleanup(?TEST_TABLE),
    Result.

concurrent_ensure_ok() ->
    cleanup(?TEST_TABLE_2),
    Self = self(),
    Creators = [spawn(fun() ->
        ok = gleamunison_tables:ensure(?TEST_TABLE_2, [set, public, named_table]),
        Self ! done
    end) || _ <- lists:seq(1, 16)],
    ok = gleamunison_tables:ensure(?TEST_TABLE_2, [set, public, named_table]),
    [receive done -> ok after 5000 -> exit(creator_timeout) end
     || _ <- Creators],
    Alive = undefined =/= ets:whereis(?TEST_TABLE_2),
    cleanup(?TEST_TABLE_2),
    Alive.

options_preserved() ->
    cleanup(?TEST_TABLE),
    ok = gleamunison_tables:ensure(
        ?TEST_TABLE, [ordered_set, public, named_table]
    ),
    Result = ets:info(?TEST_TABLE, type) =:= ordered_set
        andalso ets:info(?TEST_TABLE, protection) =:= public
        andalso ets:info(?TEST_TABLE, named_table) =:= true,
    cleanup(?TEST_TABLE),
    Result.
