-module(m_00000009).
-export(['$eval'/0]).

'$eval'() ->
    fun(Ms) ->
        timer:sleep(Ms),
        ok
    end.
