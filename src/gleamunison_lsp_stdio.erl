-module(gleamunison_lsp_stdio).
-export([init/0, write/1, read_headers/1, read_body/1]).

init() ->
    ok = io:setopts(standard_io, [binary, {encoding, latin1}]),
    nil.

write(Bin) when is_binary(Bin) ->
    ok = io:request(standard_io, {put_chars, latin1, Bin}),
    nil.

%% Latin-1 binary I/O deliberately exposes raw bytes to the framing owner.
%% A byte-at-a-time header reader never allocates an unbounded input line.
read_headers(Limit) when is_integer(Limit), Limit > 0 ->
    headers(Limit + 4, []).

headers(_, [$\n, $\r, $\n, $\r | Rest]) ->
    {ok, list_to_binary(lists:reverse(Rest))};
headers(0, _) -> {error, nil};
headers(Left, Acc) ->
    case io:request(standard_io, {get_chars, latin1, '', 1}) of
        <<Byte>> -> headers(Left - 1, [Byte | Acc]);
        _ -> {error, nil}
    end.

read_body(0) -> {ok, <<>>};
read_body(N) when is_integer(N), N > 0, N =< 1048576 ->
    case io:request(standard_io, {get_chars, latin1, '', N}) of
        Bin when is_binary(Bin), byte_size(Bin) =:= N ->
            case unicode:characters_to_binary(Bin, utf8, utf8) of
                Valid when is_binary(Valid) -> {ok, Valid};
                _ -> {error, nil}
            end;
        _ -> {error, nil}
    end;
read_body(_) -> {error, nil}.
