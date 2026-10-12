-module(m_00000038).
-export(['$eval'/0]).

%% dict-keys: M -> [K]. Enables index iteration in userspace (datalog AVET).
'$eval'() -> fun(M) -> maps:keys(M) end.
