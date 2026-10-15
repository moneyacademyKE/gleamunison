-module(m_00000002).
-export(['$eval'/0]).

%% read_line is a 0-arity builtin: each use site compiles to '$eval'() inline
%% (the RefTo convention), so the read must happen here, not in a thunk.
%% A returned fun would never be forced — the language has no zero-arg apply.
'$eval'() ->
    case io:get_line("") of
        eof -> <<>>;
        {error, _} -> <<>>;
        Line when is_list(Line) -> unicode:characters_to_binary(Line);
        Line when is_binary(Line) -> Line
    end.
