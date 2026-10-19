-module(gleamunison_static).
-export([resolve/1]).

%% Resolve once, beneath one asset root. OTP's safe_relative_path also checks
%% symlinks; a lexical prefix alone does not contain filesystem traversal.
resolve(Raw) when is_binary(Raw), byte_size(Raw) =< 4096 ->
    [Path | _] = binary:split(Raw, <<"?">>),
    try uri_string:percent_decode(Path) of
        Decoded when is_binary(Decoded) -> resolve_decoded(Decoded);
        _ -> forbidden()
    catch _:_ -> forbidden()
    end;
resolve(_) -> forbidden().

resolve_decoded(Path) ->
    Root = filename:absname(<<"priv/static">>),
    Segments = binary:split(Path, <<"/">>, [global]),
    Relative = filename:pathtype(Path) =:= relative,
    Clean = lists:all(fun(S) -> S =/= <<>> andalso S =/= <<".">> andalso S =/= <<"..">> end, Segments),
    NoAlternatePath = binary:match(Path, [<<"\\">>, <<":">>, <<0>>, <<"%">>]) =:= nomatch,
    case Relative andalso Clean andalso NoAlternatePath of
        false -> forbidden();
        true ->
            case filelib:safe_relative_path(Path, Root) of
                unsafe -> forbidden();
                Safe ->
                    Full = filename:absname(filename:join(Root, Safe)),
                    case lists:prefix(filename:split(Root), filename:split(Full)) of
                        true -> {ok, Full};
                        false -> forbidden()
                    end
            end
    end.

forbidden() -> {error, forbidden}.
