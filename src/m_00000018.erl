-module(m_00000018).
-export(['$eval'/0]).
'$eval'() -> fun(S) -> fun(P) -> fun(N) -> binary:part(S, P, N) end end end.
