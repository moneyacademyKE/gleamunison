-module(m_00000023).
-export(['$eval'/0]).
'$eval'() -> fun(F) -> fun(A) -> fun(L) -> lists:foldl(fun(X, Acc) -> erlang:apply(F, [X, Acc]) end, A, L) end end end.
