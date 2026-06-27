-module(m_state).
-export(['$eval'/0, 'state_get'/1, 'state_put'/2]).

'$eval'() -> ok.

state_get(Key) -> erlang:get(Key).

state_put(Key, Val) -> erlang:put(Key, Val), ok.
