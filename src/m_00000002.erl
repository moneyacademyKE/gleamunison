-module(m_00000002).
-export(['$eval'/0]).

'$eval'() ->
    fun() ->
        case io:get_line("") of
            eof -> <<>>;
            {error, _} -> <<>>;
            Line when is_list(Line) -> list_to_binary(Line);
            Line when is_binary(Line) -> Line
        end
    end.
