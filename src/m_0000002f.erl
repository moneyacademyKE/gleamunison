-module(m_0000002f).
-export(['$eval'/0]).
'$eval'() -> fun(M) -> fun(K) -> maps:get(K, M, null) end end.
