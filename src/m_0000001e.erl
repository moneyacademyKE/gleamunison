-module(m_0000001e).
-export(['$eval'/0]).
%% Parse a decimal integer. Bad input returns {right, bad_integer}
%% instead of raising: user text (EOF, a typo) must not kill the process.
%% {left, N} is success, matching the surface `left`/`right` constructors.
'$eval'() ->
    fun(X) ->
        try {m_f2541480, erlang:binary_to_integer(X)}
        catch error:badarg -> {m_8563bad9, bad_integer}
        end
    end.
