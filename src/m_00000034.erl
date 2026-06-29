-module(m_00000034).
-export(['$eval'/0]).

'$eval'() ->
    fun(Url) ->
        inets:start(),
        ssl:start(),
        case httpc:request(get, {binary_to_list(Url), []}, [], [{body_format, binary}]) of
            {ok, {{_, 200, _}, _Headers, Body}} -> Body;
            _ -> <<"error">>
        end
    end.
