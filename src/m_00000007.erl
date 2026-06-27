-module(m_00000007).
-export(['$eval'/0]).

'$eval'() ->
    fun(Pid) ->
        fun(Msg) ->
            Pid ! Msg,
            Msg
        end
    end.
