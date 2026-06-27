-module(m_00000017).
-export(['$eval'/0]).
'$eval'() -> fun(H) -> fun(N) -> case binary:match(H, N) of nomatch -> 0; _ -> 1 end end end.
