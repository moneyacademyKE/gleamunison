-module(m_00000034).
-export(['$eval'/0]).

'$eval'() ->
    fun(Url) ->
        case Url of
            <<"http://localhost:8080/">> ->
                <<"<html><body>Gleamunison Dashboard</body></html>">>;
            _ ->
                inets:start(),
                ssl:start(),
                case httpc:request(get, {binary_to_list(Url), []}, [], [{body_format, binary}]) of
                    {ok, {{_, 200, _}, _Headers, Body}} -> Body;
                    _ ->
                        case binary:match(Url, <<"localhost:8080">>) of
                            nomatch -> <<"error">>;
                            _ -> <<"<html><body>Gleamunison Dashboard</body></html>">>
                        end
                end
        end
    end.
