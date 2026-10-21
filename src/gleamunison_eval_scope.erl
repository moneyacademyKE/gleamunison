-module(gleamunison_eval_scope).
-behaviour(gen_server).
-export([run/2, run_bounded/5, default_budget/0, start_link/4, start_link/5, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2]).

-define(DEFAULT_MAX_PROCESSES, 1024).
-define(DEFAULT_MAX_REDUCTIONS, 10000000).
-define(DEFAULT_MAX_MEMORY, 268435456).
-define(BUDGET_TICK_MS, 10).

run(Fun, Timeout) ->
    run_bounded(Fun, Timeout, ?DEFAULT_MAX_PROCESSES, ?DEFAULT_MAX_REDUCTIONS, ?DEFAULT_MAX_MEMORY).

run_bounded(Fun, Timeout, MaxProcesses, MaxReductions, MaxMemory) ->
    case valid_budget(Timeout, MaxProcesses, MaxReductions, MaxMemory) of
        false -> {error, invalid_resource_budget};
        true ->
            Token = make_ref(),
            Budget = #{max_processes => MaxProcesses,
                       max_reductions => MaxReductions,
                       max_memory => MaxMemory},
            case gleamunison_eval_sup:start_scope(self(), Token, Fun, Timeout, Budget) of
                {ok, Scope} ->
                    Mon = monitor(process, Scope),
                    receive
                        {Token, Result} -> demonitor(Mon, [flush]), Result;
                        {'DOWN', Mon, process, Scope, Reason} -> failure(Reason)
                    end;
                {error, Reason} -> failure(Reason)
            end
    end.

default_budget() -> #{max_processes => ?DEFAULT_MAX_PROCESSES,
                      max_reductions => ?DEFAULT_MAX_REDUCTIONS,
                      max_memory => ?DEFAULT_MAX_MEMORY}.

valid_budget(Timeout, MaxProcesses, MaxReductions, MaxMemory) ->
    is_integer(Timeout) andalso Timeout > 0 andalso Timeout =< 300000 andalso
    is_integer(MaxProcesses) andalso MaxProcesses > 0 andalso MaxProcesses =< 1024 andalso
    is_integer(MaxReductions) andalso MaxReductions > 0 andalso MaxReductions =< 1000000000 andalso
    is_integer(MaxMemory) andalso MaxMemory > 0 andalso MaxMemory =< 4294967296.

start_link(Owner, Token, Fun, Timeout) ->
    start_link(Owner, Token, Fun, Timeout, default_budget()).

start_link(Owner, Token, Fun, Timeout, Budget) ->
    gen_server:start_link(?MODULE, {Owner, Token, Fun, Timeout, Budget}, []).

init({Owner, Token, Fun, Timeout}) ->
    init_scope(Owner, Token, Fun, Timeout, default_budget());
init({Owner, Token, Fun, Timeout, Budget}) ->
    init_scope(Owner, Token, Fun, Timeout, Budget).

init_scope(Owner, Token, Fun, Timeout, Budget) ->
    Scope = self(),
    {Worker, Mon} = spawn_monitor(fun() ->
        receive run -> Scope ! {evaluation_result, self(), Fun()} end
    end),
    %% set_on_spawn is inherited before a descendant runs, even when the
    %% evaluated code uses unlinked spawn or a child traps exit signals.
    erlang:trace(Worker, true, [procs, set_on_spawn, {tracer, self()}]),
    {reductions, InitialReductions} = process_info(Worker, reductions),
    Timer = erlang:send_after(Timeout, self(), deadline),
    BudgetTimer = erlang:send_after(?BUDGET_TICK_MS, self(), budget_tick),
    Worker ! run,
    {ok, #{owner => Owner, owner_mon => monitor(process, Owner), token => Token,
           worker => Worker, processes => #{Worker => Mon}, timer => Timer,
           budget_timer => BudgetTimer, budget => Budget,
           initial_reductions => InitialReductions,
           outcome => running, barrier => undefined}}.

handle_call(_, _, State) -> {reply, {error, unsupported}, State}.
handle_cast(_, State) -> {noreply, State}.

handle_info({evaluation_result, Worker, Result}, #{worker := Worker, outcome := running} = State) ->
    {noreply, finish({ok, Result}, State)};
handle_info(deadline, State) ->
    {noreply, finish({error, <<"evaluation_timeout">>}, State)};
handle_info(budget_tick, #{outcome := running} = State) ->
    case budget_exceeded(State) of
        false ->
            Timer = erlang:send_after(?BUDGET_TICK_MS, self(), budget_tick),
            {noreply, State#{budget_timer := Timer}};
        {true, Reason} ->
            {noreply, finish({error, Reason}, State)}
    end;
handle_info(budget_tick, State) ->
    {noreply, State};
handle_info({'DOWN', Mon, process, _, _}, #{owner_mon := Mon} = State) ->
    {noreply, finish({error, <<"evaluation_cancelled">>}, State)};
handle_info({trace, _, spawn, Child, _}, State) ->
    Processes = maps:get(processes, State),
    Next = State#{processes := Processes#{Child => monitor(process, Child)}, barrier := undefined},
    case {maps:get(outcome, State), map_size(Processes) < maps:get(max_processes, maps:get(budget, State))} of
        {running, true} -> {noreply, Next};
        {running, false} -> {noreply, finish({error, <<"evaluation_process_limit">>}, Next)};
        {_, _} -> exit(Child, kill), {noreply, Next}
    end;
handle_info({'DOWN', Mon, process, Pid, Reason}, State) ->
    Processes = maps:get(processes, State),
    case maps:find(Pid, Processes) of
        {ok, Mon} ->
            Next = State#{processes := maps:remove(Pid, Processes)},
            case {Pid =:= maps:get(worker, State), maps:get(outcome, State)} of
                {true, running} -> {noreply, finish(failure(Reason), Next)};
                _ -> {noreply, barrier_if_drained(Next)}
            end;
        _ -> {noreply, State}
    end;
handle_info({trace_delivered, all, Ref}, #{barrier := Ref} = State) ->
    case maps:get(outcome, State) of
        {finished, Result} ->
            maps:get(owner, State) ! {maps:get(token, State), Result},
            {stop, normal, State};
        running -> {noreply, State}
    end;
handle_info(_, State) -> {noreply, State}.

budget_exceeded(State) ->
    Budget = maps:get(budget, State),
    Processes = maps:get(processes, State),
    {Reductions, Memory} = maps:fold(fun(Pid, _Monitor, {ReductionTotal, MemoryTotal}) ->
        case process_info(Pid, [reductions, memory]) of
            undefined -> {ReductionTotal, MemoryTotal};
            Info ->
                {ReductionTotal + proplists:get_value(reductions, Info, 0),
                 MemoryTotal + proplists:get_value(memory, Info, 0)}
        end
    end, {0, 0}, Processes),
    UsedReductions = Reductions - maps:get(initial_reductions, State),
    case UsedReductions > maps:get(max_reductions, Budget) of
        true -> {true, <<"evaluation_reduction_limit">>};
        false ->
            case Memory > maps:get(max_memory, Budget) of
                true -> {true, <<"evaluation_memory_limit">>};
                false -> false
            end
    end.

finish(Result, #{outcome := running} = State) ->
    erlang:cancel_timer(maps:get(timer, State)),
    erlang:cancel_timer(maps:get(budget_timer, State)),
    maps:foreach(fun(Pid, _) -> exit(Pid, kill) end, maps:get(processes, State)),
    barrier_if_drained(State#{outcome := {finished, Result}});
finish(_, State) -> State.

%% DOWN alone is not enough: a dead parent may have spawned a child whose
%% trace is still in transit. Drain to a fixed point before replying. A late
%% spawn invalidates the barrier, is killed, and gets its own DOWN/barrier.
barrier_if_drained(#{outcome := {finished, _}, processes := Processes} = State) when map_size(Processes) =:= 0 ->
    State#{barrier := erlang:trace_delivered(all)};
barrier_if_drained(State) -> State.

terminate(_, State) ->
    maps:foreach(fun(Pid, _) -> exit(Pid, kill) end, maps:get(processes, State)),
    ok.

failure(Reason) ->
    {error, iolist_to_binary(io_lib:format("evaluation_worker_down: ~p", [Reason]))}.
