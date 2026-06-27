-module(m_00000029).
-export(['$eval'/0]).
'$eval'() -> fun(A) -> fun(B) -> {pair, A, B} end end.
