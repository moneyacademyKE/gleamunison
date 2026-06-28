-module(gleamunison_property).
-export([check/2, int_gen/0, bool_gen/0, list_gen/1, tuple_gen/2]).

check(Generator, Property) when is_function(Generator, 0), is_function(Property, 1) ->
    MaxAttempts = 100,
    check_loop(Generator, Property, MaxAttempts, []).

check_loop(_Generator, _Property, 0, Acc) ->
    {ok, lists:reverse(Acc)};
check_loop(Generator, Property, N, Acc) ->
    Value = Generator(),
    case Property(Value) of
        true ->
            check_loop(Generator, Property, N - 1, [Value | Acc]);
        {false, Reason} when is_binary(Reason) ->
            {error, #{counterexample => Value, reason => Reason, passed => length(Acc)}};
        false ->
            {error, #{counterexample => Value, reason => <<"property returned false">>, passed => length(Acc)}}
    end.

int_gen() ->
    fun() -> rand:uniform(10000) - 5000 end.

bool_gen() ->
    fun() -> rand:uniform(2) =:= 1 end.

list_gen(Gen) when is_function(Gen, 0) ->
    fun() ->
        Len = rand:uniform(10),
        [Gen() || _ <- lists:seq(1, Len)]
    end.

tuple_gen(GenA, GenB) when is_function(GenA, 0), is_function(GenB, 0) ->
    fun() -> {GenA(), GenB()} end.
