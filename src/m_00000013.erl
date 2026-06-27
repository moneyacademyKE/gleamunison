-module(m_00000013).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> case X =:= 0 of true -> case Y =:= 0 of true -> 0; false -> 1 end; false -> 1 end end end.
