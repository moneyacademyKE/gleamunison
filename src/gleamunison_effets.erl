-module(gleamunison_effets).
-export([push_frame/1, pop_frame/0, find_frame/1, do_op/4, handle_comp/2]).

%% Stack of {AbilityModule, OpIndexToFunMap} stored in process dictionary.
%% The map is a dict: OpIndex => fun((Args, Cont) -> Result).

%% push_frame(AbilityModule) ->
%%   Adds a new handler frame for the given ability. The ops dict is built
%%   from the module's exported functions named 'op_N' where N is the op index.
push_frame(AbilityMod) when is_atom(AbilityMod) ->
    Stack = case get('$ability_stack') of
        undefined -> [];
        S -> S
    end,
    %% Build ops dict by discovering exported op_N functions
    Ops = build_ops_dict(AbilityMod, 0, dict:new()),
    put('$ability_stack', [{AbilityMod, Ops} | Stack]).

build_ops_dict(Mod, N, Acc) ->
    case erlang:function_exported(Mod, list_to_atom("op_" ++ integer_to_list(N)), 2) of
        true ->
            Fun = fun(Args, Cont) ->
                erlang:apply(Mod, list_to_atom("op_" ++ integer_to_list(N)), [Args, Cont])
            end,
            build_ops_dict(Mod, N + 1, dict:store(N, Fun, Acc));
        false ->
            Acc
    end.

pop_frame() ->
    case get('$ability_stack') of
        [_ | Rest] -> put('$ability_stack', Rest);
        _ -> ok
    end.

find_frame(AbilityMod) ->
    case get('$ability_stack') of
        undefined -> none;
        Stack -> find_in_stack(Stack, AbilityMod)
    end.

find_in_stack([], _) -> none;
find_in_stack([{Mod, Ops} | Rest], AbilityMod) ->
    case Mod =:= AbilityMod of
        true -> {ok, Ops};
        false -> find_in_stack(Rest, AbilityMod)
    end.

%% do_op(AbilityMod, OpIndex, Args, Cont)
%%   Finds the handler for AbilityMod, looks up OpIndex, calls it.
do_op(AbilityMod, OpIndex, Args, Cont) ->
    case find_frame(AbilityMod) of
        {ok, Ops} ->
            case dict:find(OpIndex, Ops) of
                {ok, HandlerFun} -> HandlerFun(Args, Cont);
                error -> erlang:error({missing_operation, AbilityMod, OpIndex})
            end;
        none ->
            erlang:error({unhandled_ability, AbilityMod})
    end.

%% handle_comp(HandlerMod, Thunk)
%%   Pushes a handler frame before running Thunk, pops after.
handle_comp(HandlerMod, Thunk) ->
    push_frame(HandlerMod),
    try
        Thunk()
    after
        pop_frame()
    end.
