-module(m_00000022).
-export(['$eval'/0]).
'$eval'() -> fun(P) -> fun(L) -> lists:filter(fun(X) -> erlang:apply(P, [X]) =:= 1 end, L) end end.
