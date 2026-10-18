-module(gleamunison_cancellation).
-export([new/0, cancel/1, cancelled/1]).

new() -> atomics:new(1, []).
cancel(Token) -> atomics:put(Token, 1, 1), nil.
cancelled(Token) -> atomics:get(Token, 1) =:= 1.
