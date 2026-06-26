-module(gleamunison_effets).
-export([handle_comp/2, do_op/4]).

handle_comp(Handler, Thunk) ->
    case validate_handler(Handler) of
        true -> ok;
        false -> error({invalid_handler, Handler})
    end,
    Stack = erlang:get({gleamunison_handlers}),
    validate_stack(Stack),
    NewStack = [Handler | coerce_stack(Stack)],
    erlang:put({gleamunison_handlers}, NewStack),
    try
        Thunk()
    after
        validate_stack(Stack),
        erlang:put({gleamunison_handlers}, Stack)
    end.

do_op(AbilityKey, OpIdx, Args, Cont) ->
    Stack = erlang:get({gleamunison_handlers}),
    validate_stack(Stack),
    case find_handler(coerce_stack(Stack), AbilityKey, OpIdx) of
        {ok, HandlerFn} ->
            HandlerFn(Args, Cont);
        error ->
            error({unhandled_ability, AbilityKey, OpIdx})
    end.

coerce_stack(undefined) -> [];
coerce_stack(List) when is_list(List) -> List.

validate_stack(undefined) -> ok;
validate_stack(List) when is_list(List) ->
    lists:foreach(fun(H) ->
        case validate_handler(H) of
            true -> ok;
            false -> error({corrupted_handler_stack, H})
        end
    end, List),
    ok;
validate_stack(Other) ->
    error({invalid_handler_stack, Other}).

validate_handler(H) when is_function(H, 3) -> true;
validate_handler(Map) when is_map(Map) -> true;
validate_handler({_, F}) when is_function(F) -> true;
validate_handler({_, Map}) when is_map(Map) -> true;
validate_handler(_) -> false.

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
            case maps:find(MatchKey, Map) of
                {ok, SubHandler} -> matches_handler(SubHandler, AbilityKey, OpIdx);
                error -> error
            end;
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
