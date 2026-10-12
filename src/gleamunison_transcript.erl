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
-export([term_to_b64/1, b64_to_term/1, run_replay/2]).

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

%% Faithful serialization of raw captured values: term_to_binary under
%% base64, so a tape file carries everything replay needs. b64_to_term
%% decodes with [safe]: a tape is data a user hands back to the runtime,
%% and must never mint new atoms.
term_to_b64(Term) ->
    base64:encode(term_to_binary(Term)).

b64_to_term(B64) ->
    binary_to_term(base64:decode(B64), [safe]).

%% Replay a tape around a thunk: push one playback frame per ability key
%% found in the entries, keyed exactly as the runtime keys handlers.
%% Playback handlers serve recorded results in order via pb_next; any
%% divergence (wrong ability, wrong op, exhausted tape) raises — replay
%% is verification, and silent drift must be loud.
run_replay(Entries, Thunk) when is_list(Entries), is_function(Thunk, 0) ->
    Keys = unique_keys(Entries, []),
    Stacked = lists:foldl(
        fun(Key, Fun) ->
            fun() -> gleamunison_effets:handle_comp(playback_frame(Key, Entries), Fun) end
        end,
        Thunk,
        Keys
    ),
    Stacked().

unique_keys([], Acc) -> lists:reverse(Acc);
unique_keys([{Key, _, _, _, _} | Rest], Acc) ->
    case lists:member(Key, Acc) of
        true -> unique_keys(Rest, Acc);
        false -> unique_keys(Rest, [Key | Acc])
    end.

playback_frame(Key, Entries) ->
    Ops = maps:from_list([
        {OpIdx, fun(_Args, Cont) ->
            case pb_next(Key, OpIdx) of
                {ok, Recorded} -> Cont(Recorded);
                {error, Reason} -> error({transcript_replay, Reason})
            end
        end}
     || {K, OpIdx, _, _, _} <- Entries, K =:= Key
    ]),
    {Key, Ops}.
