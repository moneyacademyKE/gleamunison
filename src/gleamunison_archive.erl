%% Read a file embedded in the running escript's archive.
%%
%% One owner for archive access: the datalog engine and the dogfood level
%% data both ship as files rather than BEAM modules, so both read them out
%% of the same appended zip.
%%
%% The archive is located by its zip magic rather than escript:extract/2:
%% the documented `archive` section option is rejected as badarg on the OTP
%% versions this project supports (verified on OTP 29), while the appended
%% zip after the shebang line is plain and stable.
-module(gleamunison_archive).

-export([read_embedded/1]).

-spec read_embedded(binary()) -> {ok, binary()} | {error, nil}.
read_embedded(Name) ->
    try
        Script = escript:script_name(),
        case file:read_file(Script) of
            {ok, Bin} -> extract_from_archive(Bin, Name);
            _ -> {error, nil}
        end
    catch
        _:_ -> {error, nil}
    end.

extract_from_archive(Bin, Name) ->
    case binary:match(Bin, <<"PK", 3, 4>>) of
        {Pos, _} ->
            <<_:Pos/binary, Zip/binary>> = Bin,
            extract_entry(Zip, Name);
        nomatch ->
            {error, nil}
    end.

extract_entry(Zip, Name) ->
    case zip:extract(Zip, [memory, {file_list, [binary_to_list(Name)]}]) of
        {ok, [{_Entry, Data}]} -> {ok, Data};
        _ -> {error, nil}
    end.
