-module(m_0000002b).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> case X of {pair, _, B} -> B; {_, B} -> B end end.
