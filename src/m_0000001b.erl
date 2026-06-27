-module(m_0000001b).
-export(['$eval'/0]).
'$eval'() -> fun(S) -> fun(P) -> fun(R) -> binary:replace(S, P, R) end end end.
