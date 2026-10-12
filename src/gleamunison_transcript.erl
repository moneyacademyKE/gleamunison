%% Effect transcript recorder: process-dictionary log.
%%
%% do_op runs handlers in the evaluating process, so a process-dict log
%% captures every op in call order without a server process or ETS table.
%% The same machinery holds a playback cursor for replay.
%%
%% Entries are {AbilityKey, OpIdx, ArgsDynamic, ResultDynamic, Seq} tuples:
%% original values are preserved for in-process replay; serialization to
%% inspect-strings happens on the Gleam side for audit/DAG storage.
-module(gleamunison_transcript).
-export([log_start/0, log_append/4, log_entries/0, log_stop/0]).
-export([pb_start/1, pb_next/2, pb_remaining/0, pb_stop/0]).

-define(LOG_KEY, gleamunison_transcript_log).
-define(PB_KEY, gleamunison_transcript_playback).

log_start() ->
    put(?LOG_KEY, []),
    nil.

log_append(AbilityKey, OpIdx, Args, Result) ->
    Log = case get(?LOG_KEY) of
        undefined -> [];
        L when is_list(L) -> L
    end,
    Seq = length(Log),
    put(?LOG_KEY, [{AbilityKey, OpIdx, Args, Result, Seq} | Log]),
    nil.

%% Entries in call order (oldest first).
log_entries() ->
    case get(?LOG_KEY) of
        undefined -> [];
        L when is_list(L) -> lists:reverse(L)
    end.

log_stop() ->
    erase(?LOG_KEY),
    nil.

%% Playback: a FIFO of recorded entries consumed in order. pb_next checks
%% the head against the requested ability+op and returns the recorded
%% result (original value) so replay never touches the real handler.
pb_start(Entries) when is_list(Entries) ->
    put(?PB_KEY, Entries),
    nil.

pb_next(AbilityKey, OpIdx) ->
    case get(?PB_KEY) of
        [{AbilityKey, OpIdx, _Args, Result, _Seq} | Rest] ->
            put(?PB_KEY, Rest),
            {ok, Result};
        [Other | _] ->
            {error, {playback_mismatch, Other}};
        _ ->
            {error, playback_exhausted}
    end.

pb_remaining() ->
    case get(?PB_KEY) of
        undefined -> 0;
        L when is_list(L) -> length(L)
    end.

pb_stop() ->
    erase(?PB_KEY),
    nil.
