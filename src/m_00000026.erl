-module(m_00000026).
-export(['$eval'/0]).
'$eval'() -> fun(E) -> fun(L) -> case lists:member(E, L) of true -> 1; false -> 0 end end end.
