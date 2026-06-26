-module(gleamunison_effets).
-export([handle_comp/2, do_op/4]).

handle_comp(Handler, Thunk) ->
    Stack = erlang:get({gleamunison_handlers}),
    NewStack = [Handler | coerce_stack(Stack)],
    erlang:put({gleamunison_handlers}, NewStack),
    try
        Thunk()
    after
        erlang:put({gleamunison_handlers}, Stack)
    end.

do_op(AbilityKey, OpIdx, Args, Cont) ->
    Stack = coerce_stack(erlang:get({gleamunison_handlers})),
    case find_handler(Stack, AbilityKey, OpIdx) of
        {ok, HandlerFn} ->
            HandlerFn(Args, Cont);
        error ->
            error({unhandled_ability, AbilityKey, OpIdx})
    end.

coerce_stack(undefined) -> [];
coerce_stack(List) when is_list(List) -> List;
coerce_stack(_) -> [].

find_handler([Handler | Stack], AbilityKey, OpIdx) ->
    case matches_handler(Handler, AbilityKey, OpIdx) of
        {ok, HandlerFn} -> {ok, HandlerFn};
        error -> find_handler(Stack, AbilityKey, OpIdx)
    end;
find_handler([], _AbilityKey, _OpIdx) ->
    error.

keys_match(K, K) -> true;
keys_match(K1, K2) when is_atom(K1), is_binary(K2) ->
    atom_to_binary(K1, utf8) =:= K2;
keys_match(K1, K2) when is_binary(K1), is_atom(K2) ->
    K1 =:= atom_to_binary(K2, utf8);
keys_match(_, _) -> false.

matches_handler({HandlerKey, HandlerFn}, AbilityKey, _OpIdx) when is_function(HandlerFn) ->
    case keys_match(HandlerKey, AbilityKey) of
        true -> {ok, HandlerFn};
        false -> error
    end;
matches_handler({HandlerKey, Map}, AbilityKey, OpIdx) when is_map(Map) ->
    case keys_match(HandlerKey, AbilityKey) of
        true ->
            case maps:find(OpIdx, Map) of
                {ok, HandlerFn} -> {ok, HandlerFn};
                error -> error
            end;
        false -> error
    end;
matches_handler(Map, AbilityKey, OpIdx) when is_map(Map) ->
    % Search in the map keys
    Keys = maps:keys(Map),
    case find_matching_key(Keys, AbilityKey) of
        {ok, MatchKey} ->
            {ok, SubHandler} = maps:find(MatchKey, Map),
            matches_handler(SubHandler, AbilityKey, OpIdx);
        error ->
            error
    end;
matches_handler(HandlerFn, _AbilityKey, OpIdx) when is_function(HandlerFn, 3) ->
    {ok, fun(Args, Cont) -> HandlerFn(OpIdx, Args, Cont) end};
matches_handler(_, _, _) ->
    error.

find_matching_key([K | Rest], AbilityKey) ->
    case keys_match(K, AbilityKey) of
        true -> {ok, K};
        false -> find_matching_key(Rest, AbilityKey)
    end;
find_matching_key([], _) ->
    error.
