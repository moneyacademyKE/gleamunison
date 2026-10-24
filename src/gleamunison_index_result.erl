-module(gleamunison_index_result).
-export([strings/1]).

%% The Datalog CLI carrier is Erlang's ~tp rendering. Decode with its native
%% term reader, never eval, so numeric UTF-8 binaries and escaped text retain
%% their bytes. Accept only the list-of-text result shape promised by queries.
strings(Output) when is_binary(Output) ->
    Lines = [Line || Line <- binary:split(Output, <<"\n">>, [global]),
                      not is_definition_notice(Line)],
    Text = iolist_to_binary(lists:join(<<"\n">>, Lines)),
    try
        {ok, Tokens, _} = erl_scan:string(binary_to_list(Text) ++ "."),
        {ok, Value} = erl_parse:parse_term(Tokens),
        true = is_list(Value),
        true = lists:all(fun valid_text/1, Value),
        {ok, Value}
    catch _:_ -> {error, <<"invalid Datalog string-list result">>}
    end.

is_definition_notice(<<"(defined ", _/binary>>) -> true;
is_definition_notice(_) -> false.

valid_text(Bin) when is_binary(Bin) ->
    is_binary(unicode:characters_to_binary(Bin, utf8, utf8));
valid_text(_) -> false.
