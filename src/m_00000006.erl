-module(m_00000006).
-export(['$eval'/0]).

'$eval'() ->
    erlang:self().
