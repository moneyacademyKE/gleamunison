-module(m_0000000f).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> case X =:= Y of true -> 1; false -> 0 end end end.
