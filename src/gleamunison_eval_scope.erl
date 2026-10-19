-module(gleamunison_eval_scope).
-behaviour(gen_server).
-export([run/2, start_link/4, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2]).

run(Fun, Timeout) ->
    Token = make_ref(),
    case gleamunison_eval_sup:start_scope(self(), Token, Fun, Timeout) of
        {ok, Scope} ->
            Mon = monitor(process, Scope),
            receive
                {Token, Result} -> demonitor(Mon, [flush]), Result;
                {'DOWN', Mon, process, Scope, Reason} -> failure(Reason)
            end;
        {error, Reason} -> failure(Reason)
    end.

start_link(Owner, Token, Fun, Timeout) ->
    gen_server:start_link(?MODULE, {Owner, Token, Fun, Timeout}, []).

init({Owner, Token, Fun, Timeout}) ->
    Scope = self(),
    {Worker, Mon} = spawn_monitor(fun() ->
        receive run -> Scope ! {evaluation_result, self(), Fun()} end
    end),
    %% set_on_spawn is inherited before a descendant runs, even when the
    %% evaluated code uses unlinked spawn or a child traps exit signals.
    erlang:trace(Worker, true, [procs, set_on_spawn, {tracer, self()}]),
    Timer = erlang:send_after(Timeout, self(), deadline),
    Worker ! run,
    {ok, #{owner => Owner, owner_mon => monitor(process, Owner), token => Token,
           worker => Worker, processes => #{Worker => Mon}, timer => Timer,
           outcome => running, barrier => undefined}}.

handle_call(_, _, State) -> {reply, {error, unsupported}, State}.
handle_cast(_, State) -> {noreply, State}.

handle_info({evaluation_result, Worker, Result}, #{worker := Worker, outcome := running} = State) ->
    {noreply, finish({ok, Result}, State)};
handle_info(deadline, State) ->
    {noreply, finish({error, <<"evaluation_timeout">>}, State)};
handle_info({'DOWN', Mon, process, _, _}, #{owner_mon := Mon} = State) ->
    {noreply, finish({error, <<"evaluation_cancelled">>}, State)};
handle_info({trace, _, spawn, Child, _}, State) ->
    Processes = maps:get(processes, State),
    Next = State#{processes := Processes#{Child => monitor(process, Child)}, barrier := undefined},
    case maps:get(outcome, State) of
        running when map_size(Processes) < 1024 -> {noreply, Next};
        running -> {noreply, finish({error, <<"evaluation_process_limit">>}, Next)};
        _ -> exit(Child, kill), {noreply, Next}
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

finish(Result, #{outcome := running} = State) ->
    erlang:cancel_timer(maps:get(timer, State)),
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
