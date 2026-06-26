-module(m_00000001).
-export(['$eval'/0]).

'$eval'() ->
    fun(X) ->
        fun(Y) ->
            X + Y
        end
    end.
