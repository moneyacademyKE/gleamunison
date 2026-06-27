-module(m_0000001c).
-export(['$eval'/0]).
'$eval'() -> fun(S) -> fun(D) -> binary:split(S, D, [global]) end end.
