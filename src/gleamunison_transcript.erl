%% Effect transcript recorder: token-keyed process-dictionary tapes.
%%
%% do_op runs handlers in the evaluating process, so a process-dict log
%% captures every op in call order without a server process or ETS table.
%% Each recorder/playback handle owns a unique token, so two tapes in the
%% same process cannot silently clobber one another.
%%
%% Entries are {AbilityKey, OpIdx, ArgsDynamic, ResultDynamic, Seq} tuples:
%% original values are preserved for in-process replay; serialization to
%% inspect-strings happens on the Gleam side for audit/DAG storage.
-module(gleamunison_transcript).
-export([new_token/0]).
-export([log_start/1, log_append/5, log_entries/1, log_stop/1]).
-export([pb_start/2, pb_next/3, pb_remaining/1, pb_stop/1]).
-export([term_to_b64/1, b64_to_term/1, run_replay/3]).

-define(LOG_KEY, gleamunison_transcript_log).
-define(PB_KEY, gleamunison_transcript_playback).

new_token() ->
    make_ref().

log_start(Token) ->
    put({?LOG_KEY, Token}, []),
    nil.

log_append(Token, AbilityKey, OpIdx, Args, Result) ->
    case get({?LOG_KEY, Token}) of
        Log when is_list(Log) ->
            Seq = length(Log),
            put({?LOG_KEY, Token}, [{AbilityKey, OpIdx, Args, Result, Seq} | Log]),
            nil;
        _ ->
            nil
    end.

%% Entries in call order (oldest first).
log_entries(Token) ->
    case get({?LOG_KEY, Token}) of
        Log when is_list(Log) -> lists:reverse(Log);
        _ -> []
    end.

log_stop(Token) ->
    erase({?LOG_KEY, Token}),
    nil.

%% Playback: a FIFO of recorded entries consumed in order. pb_next checks
%% the head against the requested ability+op and returns the recorded
%% result (original value) so replay never touches the real handler.
pb_start(Token, Entries) when is_list(Entries) ->
    put({?PB_KEY, Token}, Entries),
    nil.

pb_next(Token, AbilityKey, OpIdx) ->
    case get({?PB_KEY, Token}) of
        [{AbilityKey, OpIdx, _Args, Result, _Seq} | Rest] ->
            put({?PB_KEY, Token}, Rest),
            {ok, Result};
        [Other | _] ->
            {error, {playback_mismatch, Other}};
        _ ->
            {error, playback_exhausted}
    end.

pb_remaining(Token) ->
    case get({?PB_KEY, Token}) of
        Entries when is_list(Entries) -> length(Entries);
        _ -> 0
    end.

pb_stop(Token) ->
    erase({?PB_KEY, Token}),
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
run_replay(Token, Entries, Thunk) when is_list(Entries), is_function(Thunk, 0) ->
    Keys = unique_keys(Entries, []),
    Stacked = lists:foldl(
        fun(Key, Fun) ->
            fun() -> gleamunison_effects:handle_comp(playback_frame(Token, Key, Entries), Fun) end
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

playback_frame(Token, Key, Entries) ->
    Ops = maps:from_list([
        {OpIdx, fun(_Args, Cont) ->
            case pb_next(Token, Key, OpIdx) of
                {ok, Recorded} -> Cont(Recorded);
                {error, Reason} -> error({transcript_replay, Reason})
            end
        end}
     || {K, OpIdx, _, _, _} <- Entries, K =:= Key
    ]),
    {Key, Ops}.
