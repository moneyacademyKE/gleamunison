-module(gleamunison_static).
-export([resolve/1, read/1, asset_root/0]).

%% Resolve once, beneath one asset root. OTP's safe_relative_path also checks
%% symlinks; a lexical prefix alone does not contain filesystem traversal.
%%
%% Roots are tried in order: the cwd-relative priv/static (dev, repo root),
%% then the loaded application's priv dir (Hex consumers, installs). The
%% escript has neither on disk, so read/1 falls through to the archive.

asset_root() ->
    Candidates = [filename:absname(<<"priv/static">>) | app_static_dirs()],
    case [D || D <- Candidates, filelib:is_dir(D)] of
        [Root | _] -> Root;
        [] -> filename:absname(<<"priv/static">>)
    end.

app_static_dirs() ->
    case code:priv_dir(gleamunison) of
        {error, _} -> [];
        Dir -> [filename:join(Dir, "static")]
    end.

resolve(Raw) when is_binary(Raw), byte_size(Raw) =< 4096 ->
    [Path | _] = binary:split(Raw, <<"?">>),
    try uri_string:percent_decode(Path) of
        Decoded when is_binary(Decoded) -> resolve_decoded(Decoded);
        _ -> forbidden()
    catch _:_ -> forbidden()
    end;
resolve(_) -> forbidden().

resolve_decoded(Path) ->
    case clean_relative(Path) of
        {error, _} = Error -> Error;
        {ok, Safe} ->
            Root = asset_root(),
            Full = filename:absname(filename:join(Root, Safe)),
            case lists:prefix(filename:split(Root), filename:split(Full)) of
                true -> {ok, Full};
                false -> forbidden()
            end
    end.

%% Read an asset from wherever it lives. The archive is the only carrier
%% inside a shipped escript: priv/static is not unpacked next to the script.
read(Raw) ->
    case resolve(Raw) of
        {ok, FullPath} ->
            case file:read_file(FullPath) of
                {ok, Content} -> {ok, Content};
                {error, _} -> read_archive(Raw)
            end;
        {error, _} ->
            read_archive(Raw)
    end.

read_archive(Raw) when is_binary(Raw) ->
    [Path | _] = binary:split(Raw, <<"?">>),
    try uri_string:percent_decode(Path) of
        Decoded when is_binary(Decoded) ->
            case clean_relative(Decoded) of
                {ok, Safe} ->
                    Entry = <<"priv/static/", Safe/binary>>,
                    gleamunison_archive:read_embedded(Entry);
                {error, _} -> forbidden()
            end;
        _ -> forbidden()
    catch _:_ -> forbidden()
    end;
read_archive(_) -> forbidden().

%% One traversal rule for both carriers: relative, no empty/./.. segments,
%% no alternate-path characters.
clean_relative(Path) ->
    Segments = binary:split(Path, <<"/">>, [global]),
    Relative = filename:pathtype(Path) =:= relative,
    Clean = lists:all(fun(S) -> S =/= <<>> andalso S =/= <<".">> andalso S =/= <<"..">> end, Segments),
    NoAlternatePath = binary:match(Path, [<<"\\">>, <<":">>, <<0>>, <<"%">>]) =:= nomatch,
    case Relative andalso Clean andalso NoAlternatePath of
        true ->
            case filelib:safe_relative_path(Path, asset_root()) of
                unsafe -> forbidden();
                Safe -> {ok, Safe}
            end;
        false -> forbidden()
    end.

forbidden() -> {error, forbidden}.
