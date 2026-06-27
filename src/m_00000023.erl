-module(m_00000023).
-export(['$eval'/0]).
'$eval'() -> fun(F) -> fun(A) -> fun(L) -> lists:foldl(fun(X, Acc) -> erlang:apply(erlang:apply(F, [Acc]), [X]) end, A, L) end end end.
