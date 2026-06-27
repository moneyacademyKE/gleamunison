-module(m_00000005).
-export(['$eval'/0]).

'$eval'() ->
    fun(Fun) when is_function(Fun) ->
        erlang:spawn(Fun)
    end.
