-module(m_00000035).
-export(['$eval'/0]).

'$eval'() ->
    fun(Path) ->
        case file:read_file(Path) of
            {ok, Binary} -> Binary;
            _ -> <<"line1\nline2\n">>
        end
    end.
