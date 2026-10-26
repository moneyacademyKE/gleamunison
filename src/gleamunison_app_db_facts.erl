%% Pure EAV data operations for the application database. No process, file, or
%% code-CAS access lives here: replay and reads are ordinary data transforms.
-module(gleamunison_app_db_facts).
-export([validate_changes/2, apply_transaction/3, replay/1, next_tx/1, get/3, find/3]).

validate_changes(Assertions, Retractions) when is_list(Assertions), is_list(Retractions) ->
    try
        lists:foreach(fun valid_fact/1, Assertions ++ Retractions),
        {ok, nil}
    catch
        throw:Reason -> {error, Reason}
    end;
validate_changes(_, _) -> {error, <<"transaction changes must be lists">>}.

valid_fact({pair, Entity, {pair, Attribute, Value}})
  when is_binary(Entity), is_binary(Attribute), is_binary(Value),
       byte_size(Entity) =< 65536, byte_size(Attribute) =< 65536,
       byte_size(Value) =< 1048576 -> ok;
valid_fact(_) -> throw(<<"facts must be (pair entity (pair attribute text-value))">>).

apply_transaction(Facts, Assertions, Retractions) ->
    RetractionKeys = [fact_key(Fact) || Fact <- Retractions],
    Remaining = maps:without(RetractionKeys, Facts),
    lists:foldl(fun(Fact, Acc) -> maps:put(fact_key(Fact), Fact, Acc) end,
                Remaining, Assertions).

fact_key({pair, Entity, {pair, Attribute, Value}}) -> {Entity, Attribute, Value}.

%% Only committed journal records are replayed. A single DETS insert+sync is
%% the commit boundary; the current fact set is derived, never a second truth.
replay(Tab) ->
    Journal = journal(Tab),
    lists:foldl(fun({_Tx, Assertions, Retractions}, Facts) ->
        apply_transaction(Facts, Assertions, Retractions)
    end, #{}, Journal).

next_tx(Tab) ->
    case journal(Tab) of
        [] -> 1;
        Records -> lists:max([Tx || {Tx, _, _} <- Records]) + 1
    end.

journal(Tab) ->
    Records = dets:foldl(fun
        ({{transaction, Tx}, {Assertions, Retractions}}, Acc)
          when is_integer(Tx), Tx > 0, is_list(Assertions), is_list(Retractions) ->
            [{Tx, Assertions, Retractions} | Acc];
        (_, Acc) -> Acc
    end, [], Tab),
    lists:keysort(1, Records).

get(Facts, Entity, Attribute) ->
    lists:sort([Fact || {{E, A, _}, Fact} <- maps:to_list(Facts),
                         E =:= Entity, A =:= Attribute]).

find(Facts, Attribute, Value) ->
    lists:sort([Fact || {{_, A, V}, Fact} <- maps:to_list(Facts),
                         A =:= Attribute, V =:= Value]).
