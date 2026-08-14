-module(m_00000005).
-export(['$eval'/0]).

'$eval'() ->
    fun(Fun) when is_function(Fun) ->
        case erlang:fun_info(Fun, arity) of
            {arity, 0} -> erlang:spawn(Fun);
            {arity, 1} -> erlang:spawn(fun() -> Fun(0) end);
            _ -> erlang:spawn(Fun)
        end
    end.
