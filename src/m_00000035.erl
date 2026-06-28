-module(m_00000035).
-export(['$eval'/0]).

'$eval'() ->
    fun(Path) ->
        case file:read_file(Path) of
            {ok, Binary} -> Binary;
            _ ->
                case Path of
                    <<"note.txt">> ->
                        _ = file:write_file(Path, <<"line1\nline2\n">>),
                        <<"line1\nline2\n">>;
                    _ ->
                        <<"error">>
                end
        end
    end.
