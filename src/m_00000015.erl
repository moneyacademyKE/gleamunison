-module(m_00000015).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> fun(Y) -> <<X/binary, Y/binary>> end end.
