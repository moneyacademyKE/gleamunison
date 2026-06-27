-module(m_00000032).
-export(['$eval'/0]).
'$eval'() -> fun(S) -> fun(E) -> sets:add_element(E, S) end end.
