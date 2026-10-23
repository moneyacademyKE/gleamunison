%% The store's own record of what happened to it.
%%
%% Two append-only logs live beside the store file, each a dets table keyed by a
%% monotonic sequence number so appends never overwrite and reading back is a
%% full traversal in insertion order:
%%
%%   content_log.dets    {Seq, RefHex, Kind, At}   what entered the store
%%   exec_log.dets       {Seq, RefHex, Outcome, Reason, Caller, At}  what ran
%%
%% They are separate from the store on purpose. The store is content-addressed
%% and immutable; a log is time-ordered and mutable-by-append. Writing a log
%% entry into the store would put a changing fact behind a hash that cannot
%% change.
-module(gleamunison_store_log).
-export([
    append_content/4, tail_content/2,
    append_exec/6, tail_exec/2, merged_tail/2
]).

content_file() -> "content_log.dets".
exec_file() -> "exec_log.dets".

%% Append one content entry: ref entered the store, of this kind, at this time.
append_content(Dir, RefHex, Kind, At) ->
    append(filename:join(binary_to_list(Dir), content_file()),
           {RefHex, Kind, At}).

%% Append one execution entry: what was run, how it ended, why, who, when.
append_exec(Dir, RefHex, Outcome, Reason, Caller, At) ->
    append(filename:join(binary_to_list(Dir), exec_file()),
           {RefHex, Outcome, Reason, Caller, At}).

tail_content(Dir, N) ->
    tail(filename:join(binary_to_list(Dir), content_file()), N).

tail_exec(Dir, N) ->
    case tail(filename:join(binary_to_list(Dir), exec_file()), N) of
        {ok, Rows} -> {ok, [normalize_exec(R) || R <- Rows]};
        {error, Reason} -> {error, Reason}
    end.

%% Rows written before the caller field existed lack it. Normalizing on read
%% keeps one shape for every consumer instead of making each of them guess.
normalize_exec({RefHex, Outcome, Reason, Caller, At}) ->
    {RefHex, Outcome, Reason, Caller, At};
normalize_exec({RefHex, Outcome, Reason, At}) ->
    {RefHex, Outcome, Reason, <<"unknown">>, At}.

%% Both logs in one chronological view: what the store has seen, oldest first.
%% Every row is the same shape so a caller decodes one type:
%%   {Kind, RefHex, Label, Detail, At}
%% content: Label = what kind of content (term, sync), Detail = ""
%% exec:    Label = outcome (ok, refused), Detail = the reason, or ""
merged_tail(Dir, N) when is_integer(N), N > 0 ->
    case {tail_content(Dir, N), tail_exec(Dir, N)} of
        {{ok, Content}, {ok, Exec}} ->
            Rows = [row_content(E) || E <- Content] ++ [row_exec(E) || E <- Exec],
            Sorted = lists:keysort(5, Rows),
            Keep = min(N, length(Sorted)),
            {ok, lists:nthtail(length(Sorted) - Keep, Sorted)};
        {{error, R}, _} -> {error, R};
        {_, {error, R}} -> {error, R}
    end;
merged_tail(_Dir, N) ->
    {error, list_to_binary(io_lib:format("merged_tail needs a positive count, got ~p", [N]))}.

row_content({RefHex, Kind, At}) -> {<<"content">>, RefHex, Kind, <<>>, At}.

%% Exec rows gained a caller field after the first release, so an older table
%% holds {Ref, Outcome, Reason, At}. A log must not lose history because the
%% format grew: both shapes read.
row_exec({RefHex, Outcome, Reason, _Caller, At}) ->
    {<<"exec">>, RefHex, Outcome, Reason, At};
row_exec({RefHex, Outcome, Reason, At}) ->
    {<<"exec">>, RefHex, Outcome, Reason, At}.

%% Append with the next sequence number. dets:info(size) is the count of keys,
%% and keys are exactly 1..size, so size+1 is the next one. One writer at a
%% time: the CLI opens the table per command and closes it.
append(Path, Payload) ->
    case open(Path) of
        {error, Reason} -> {error, Reason};
        {ok, Tab} ->
            Result =
                try
                    Seq = dets:info(Tab, size) + 1,
                    ok = dets:insert(Tab, {Seq, Payload}),
                    ok = dets:sync(Tab),
                    {ok, Seq}
                catch
                    Class:Reason -> {error, format_error(Class, Reason)}
                end,
            _ = dets:close(Tab),
            Result
    end.

%% The last N entries, oldest first. dets has no tab2list (that is ets), so the
%% table is folded into a list and sorted by sequence number.
tail(Path, N) when is_integer(N), N > 0 ->
    case open(Path) of
        {error, Reason} -> {error, Reason};
        {ok, Tab} ->
            Result =
                try
                    All = dets:foldl(fun(E, Acc) -> [E | Acc] end, [], Tab),
                    Sorted = lists:keysort(1, All),
                    Entries = [P || {_Seq, P} <- Sorted],
                    Keep = min(N, length(Entries)),
                    {ok, lists:nthtail(length(Entries) - Keep, Entries)}
                catch
                    Class:Reason -> {error, format_error(Class, Reason)}
                end,
            _ = dets:close(Tab),
            Result
    end;
tail(_Path, N) ->
    {error, list_to_binary(io_lib:format("tail needs a positive count, got ~p", [N]))}.

open(Path) ->
    case filelib:ensure_dir(Path) of
        ok ->
            Name = stable_name(Path),
            case dets:open_file(Name, [{file, Path}, {type, set}]) of
                {ok, Name} -> {ok, Name};
                {error, Reason} -> {error, format_error(dets, Reason)}
            end;
        {error, Reason} ->
            {error, format_error(file, Reason)}
    end.

%% dets table names must be atoms; the file path is not, so hash it to a stable
%% small atom rather than leaking one atom per path.
stable_name(Path) ->
    Hex = binary:encode_hex(crypto:hash(sha256, unicode:characters_to_binary(Path))),
    binary_to_atom(<<"gleamunison_store_log_", (binary:part(Hex, 0, 16))/binary>>, utf8).

format_error(Class, Reason) ->
    iolist_to_binary(io_lib:format("~p:~p", [Class, Reason])).
