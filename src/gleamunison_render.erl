-module(gleamunison_render).
-export([term/1, setup_stdio/0]).

%% How a runtime value is shown to a human.
%%
%% The contract is Erlang term notation, because that is what `run` promises and
%% what a caller re-parses. `~tp` alone is not good enough for text: it only
%% prints a binary as a string when every byte is printable Latin-1, so a UTF-8
%% value comes out as <<104,195,169,108,108,111>> — technically the term, useless
%% as an answer. Binaries that hold valid UTF-8 are rendered as text with the
%% quotes and escapes a literal needs; every other term falls through to ~tp,
%% which already knows how to show tuples, maps, funs, pids, and refs.

term(Term) ->
    unicode:characters_to_binary(render(Term, 0)).

-define(MAX_DEPTH, 32).

render(_, Depth) when Depth > ?MAX_DEPTH ->
    <<"...">>;
render(Bin, _Depth) when is_binary(Bin) ->
    case unicode:characters_to_binary(Bin, utf8, utf8) of
        Bin ->
            case printable(Bin) of
                %% `<<"...">>` is the shape the REPL already uses for text, so
                %% both paths spell a value the same way. The bytes inside are
                %% the text itself, not a byte list.
                true -> [<<"<<\"">>, escape(Bin), <<"\">>">>];
                false -> bytes(Bin)
            end;
        %% Not decodable as UTF-8, so it is not text. ~tp would still print
        %% byte 255 as <<"ÿ">> because it assumes Latin-1; a byte list is the
        %% only shape that cannot be mistaken for decoded text.
        _ -> bytes(Bin)
    end;
render(List, Depth) when is_list(List) ->
    [$[, lists:join(", ", [render(E, Depth + 1) || E <- List]), $]];
render(Tuple, Depth) when is_tuple(Tuple) ->
    Elements = tuple_to_list(Tuple),
    [${, lists:join(", ", [render(E, Depth + 1) || E <- Elements]), $}];
render(Map, Depth) when is_map(Map) ->
    Pairs = maps:to_list(Map),
    [${, lists:join(", ", [
        [render(K, Depth + 1), " => ", render(V, Depth + 1)]
        || {K, V} <- Pairs
    ]), $}];
render(Other, _) ->
    io_lib:format("~tp", [Other]).

%% A binary is shown as text when it decodes and carries no control bytes other
%% than the ones a literal can escape. A payload that is not text stays bytes.
printable(<<>>) -> true;
printable(<<C/utf8, Rest/binary>>) when C >= 16#20, C =/= 16#7F ->
    printable(Rest);
printable(<<C, Rest/binary>>) when C =:= $\n; C =:= $\t; C =:= $\r ->
    printable(Rest);
printable(_) -> false.

%% A binary that is not text: show the bytes, comma separated, so nothing
%% mistakes it for a decoded string.
bytes(Bin) ->
    [<<"<<">>, lists:join(", ", [integer_to_list(B) || <<B>> <= Bin]), <<">>">>].

escape(Bin) ->
    escape(Bin, []).

escape(<<>>, Acc) ->
    lists:reverse(Acc);
escape(<<$", Rest/binary>>, Acc) ->
    escape(Rest, ["\\\"" | Acc]);
escape(<<$\\, Rest/binary>>, Acc) ->
    escape(Rest, ["\\\\" | Acc]);
escape(<<$\n, Rest/binary>>, Acc) ->
    escape(Rest, ["\\n" | Acc]);
escape(<<$\t, Rest/binary>>, Acc) ->
    escape(Rest, ["\\t" | Acc]);
escape(<<$\r, Rest/binary>>, Acc) ->
    escape(Rest, ["\\r" | Acc]);
escape(<<C/utf8, Rest/binary>>, Acc) ->
    escape(Rest, [<<C/utf8>> | Acc]);
escape(<<C, Rest/binary>>, Acc) ->
    escape(Rest, [io_lib:format("\\x{~2.16.0B}", [C]) | Acc]).

%% The console is a latin1 device by default, which is why io:format("~ts") on
%% text outside Latin-1 escapes every codepoint as \x{...}. Asking for a unicode
%% device once, at startup, makes every later write carry the real bytes. The
%% LSP pump sets its own latin1+binary opts when it needs byte framing, so it
%% still wins for its own stream.
setup_stdio() ->
    _ = io:setopts(standard_io, [{encoding, unicode}]),
    _ = io:setopts(standard_error, [{encoding, unicode}]),
    nil.
