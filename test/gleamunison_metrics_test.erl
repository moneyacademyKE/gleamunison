-module(gleamunison_metrics_test).
-export([histogram_entries/0, counter_survives_creator/0, registry_is_bounded/0,
         counter_accumulates/0, supervisor_recovers_owner/0]).

histogram_entries() ->
    Name = <<"readiness-test.histogram">>,
    [gleamunison_metrics:histogram(Name, N) || N <- lists:seq(1, 4096)],
    Values = [Value || {{histogram, Stored, _}, Value} <- gleamunison_metrics:list_metrics(),
                       Stored =:= Name],
    %% Slots must contain the latest observations, not an arbitrary prefix.
    true = lists:min(Values) >= 3969,
    length(Values).

counter_survives_creator() ->
    Name = <<"readiness-test.short-lived-counter">>,
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        gleamunison_metrics:counter(Name, 7),
        Parent ! {counter_written, self()}
    end),
    receive {counter_written, Pid} -> ok after 2000 -> error(counter_timeout) end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok after 2000 -> error(counter_owner_leak) end,
    lists:keyfind({counter, Name}, 1, gleamunison_metrics:list_metrics()) =:= {{counter, Name}, 7}.

counter_accumulates() ->
    Name = <<"readiness-test.atomic-counter">>,
    [gleamunison_metrics:counter(Name, 1) || _ <- lists:seq(1, 1000)],
    lists:keyfind({counter, Name}, 1, gleamunison_metrics:list_metrics()) =:= {{counter, Name}, 1000}.

supervisor_recovers_owner() ->
    _ = gleamunison_metrics:list_metrics(),
    Pid = whereis(gleamunison_metrics),
    true = is_pid(Pid),
    Monitor = erlang:monitor(process, Pid),
    exit(Pid, kill),
    receive {'DOWN', Monitor, process, Pid, _} -> ok after 1000 -> error(owner_not_stopped) end,
    wait_for_owner(Pid, 50).

wait_for_owner(_, 0) -> false;
wait_for_owner(Previous, Attempts) ->
    case whereis(gleamunison_metrics) of
        Pid when is_pid(Pid), Pid =/= Previous ->
            gleamunison_metrics:counter(<<"after-restart">>, 1),
            lists:keyfind({counter, <<"after-restart">>}, 1, gleamunison_metrics:list_metrics())
                =:= {{counter, <<"after-restart">>}, 1};
        _ -> timer:sleep(10), wait_for_owner(Previous, Attempts - 1)
    end.

registry_is_bounded() ->
    gleamunison_metrics:counter(binary:copy(<<"x">>, 129), 1),
    gleamunison_metrics:counter(<<>>, 1),
    [gleamunison_metrics:gauge(integer_to_binary(N), N) || N <- lists:seq(1, 1024)],
    Entries = gleamunison_metrics:list_metrics(),
    Keys = lists:usort([{element(1, Key), element(2, Key)} || {Key, _} <- Entries]),
    length(Keys) =< 256 andalso
        lists:all(fun({_Kind, Name}) -> byte_size(Name) > 0 andalso byte_size(Name) =< 128 end, Keys).
