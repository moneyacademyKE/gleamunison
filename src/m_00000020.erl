-module(m_00000020).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> lists:reverse(X) end.
