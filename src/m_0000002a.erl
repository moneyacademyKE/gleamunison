-module(m_0000002a).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> case X of {pair, A, _} -> A; {_, A} -> A end end.
