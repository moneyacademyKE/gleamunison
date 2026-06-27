-module(m_00000033).
-export(['$eval'/0]).

'$eval'() ->
    fun(JsonStr) ->
        try
            Decoded = json:decode(JsonStr),
            convert(Decoded)
        catch
            _:_ -> <<"error">>
        end
    end.

convert(Map) when is_map(Map) ->
    maps:fold(fun(K, V, Acc) -> [[K, convert(V)] | Acc] end, [], Map);
convert(List) when is_list(List) ->
    [convert(X) || X <- List];
convert(Val) -> Val.
