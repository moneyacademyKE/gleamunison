-module(gleamunison_ffi_test).
-export([test_storage_owner_survives/0, test_effects_runtime/0]).

test_storage_owner_survives() ->
    Parent = self(),
    Ref = make_ref(),
    spawn(fun() ->
        Tab = gleamunison_storage:new(),
        Parent ! {Ref, Tab}
    end),
    Tab = receive
        {Ref, T} -> T
    after 1000 ->
        error(timeout)
    end,
    timer:sleep(100),
    {ok, nil} = gleamunison_storage:insert(Tab, <<"mykey">>, <<"myval">>),
    case gleamunison_storage:lookup(Tab, <<"mykey">>) of
        {ok, {some, <<"myval">>}} -> {ok, nil};
        Other -> {error, list_to_binary(io_lib:format("unexpected ~p", [Other]))}
    end.

test_effects_runtime() ->
    Handler = fun(Args, Cont) -> Cont([list_to_binary(lists:reverse(binary_to_list(hd(Args))))]) end,
    Result = gleamunison_effets:handle_comp(
        {<<"ability1">>, Handler},
        fun() ->
            gleamunison_effets:do_op(<<"ability1">>, 0, [<<"hello">>], fun(R) -> R end)
        end
    ),
    case Result of
        [<<"olleh">>] -> {ok, nil};
        Other -> {error, list_to_binary(io_lib:format("unexpected ~p", [Other]))}
    end.
