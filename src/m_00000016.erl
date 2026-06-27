-module(m_00000016).
-export(['$eval'/0]).
'$eval'() -> fun(X) -> erlang:byte_size(X) end.
