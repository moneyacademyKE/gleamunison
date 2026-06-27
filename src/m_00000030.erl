-module(m_00000030).
-export(['$eval'/0]).
'$eval'() -> fun(M) -> fun(K) -> fun(V) -> maps:put(K, V, M) end end end.
