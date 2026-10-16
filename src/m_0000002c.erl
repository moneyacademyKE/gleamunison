-module(m_0000002c).
-export(['$eval'/0]).
%% Must match the tuple a `(left n)` pattern compiles to: the module
%% name is the last 8 of sha256("left"), not the atom `left`.
'$eval'() -> fun(X) -> {m_f2541480, X} end.
