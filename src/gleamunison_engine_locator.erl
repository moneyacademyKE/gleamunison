%% Locate the native datalog engine (ADR-0062).
%%
%% The engine is Lisp source, not BEAM modules, so it cannot ride the code
%% path. Three carriers exist, in resolution order:
%%
%%   1. the escript archive (priv/datalog/*.lisp embedded) - any directory
%%   2. the loaded application's priv dir        - Hex consumers, installs
%%   3. the repository (priv/datalog, then gleamunison_datalog/src) - dev
%%
%% Both functions fail closed with {error, nil}: no path guessing, no
%% silent fallback to a stale copy.
-module(gleamunison_engine_locator).

-export([read_embedded/1, priv_datalog_dir/0]).

%% Read one engine file out of the running escript's embedded archive.
%% Outside an escript (gleam run, gleam test) this returns not-found.
-spec read_embedded(binary()) -> {ok, binary()} | {error, nil}.
read_embedded(Name) ->
    gleamunison_archive:read_embedded(Name).

%% Absolute priv/datalog directory of the loaded application. This is what
%% makes the engine work for a Hex consumer, whose cwd is their own project.
-spec priv_datalog_dir() -> {ok, binary()} | {error, nil}.
priv_datalog_dir() ->
    case code:priv_dir(gleamunison) of
        {error, _} ->
            {error, nil};
        Dir ->
            Datalog = filename:join(Dir, "datalog"),
            case filelib:is_dir(Datalog) of
                true -> {ok, list_to_binary(Datalog)};
                false -> {error, nil}
            end
    end.
