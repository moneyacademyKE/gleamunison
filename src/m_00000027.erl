-module(m_00000027).
-export(['$eval'/0]).
'$eval'() -> fun(F) -> fun(T) -> lists:seq(F, T) end end.
