-module(m_00000024).
-export(['$eval'/0]).
'$eval'() -> fun(A) -> fun(B) -> A ++ B end end.
