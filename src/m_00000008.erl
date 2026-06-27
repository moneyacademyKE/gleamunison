-module(m_00000008).
-export(['$eval'/0]).

'$eval'() ->
    receive
        Msg -> Msg
    end.
