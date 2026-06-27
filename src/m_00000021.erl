-module(m_00000021).
-export(['$eval'/0]).
'$eval'() -> fun(F) -> fun(L) -> lists:map(fun(X) -> erlang:apply(F, [X]) end, L) end end.
