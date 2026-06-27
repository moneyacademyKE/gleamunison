-module(m_00000012).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> case X =/= 0 andalso Y =/= 0 of true -> 1; false -> 0 end end end.
