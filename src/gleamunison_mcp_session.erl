-module(gleamunison_mcp_session).
-behaviour(gen_server).
-define(MAX_REQUESTS, 64).
-export([start_link/1, start/1, stop/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2]).

start(LoadFiles) when is_list(LoadFiles) ->
    case gleamunison_runtime_sup:start_mcp(LoadFiles) of
        {ok, _Pid} -> {ok, nil};
        {error, already_started} -> {error, <<"mcp session already running">>};
        {error, Reason} -> {error, Reason}
    end.

start_link(LoadFiles) when is_list(LoadFiles) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, LoadFiles, []).

stop() ->
    gleamunison_runtime_sup:stop_mcp(),
    nil.

init(LoadFiles) ->
    State0 = gleamunison@mcp_session:boot(),
    case load_files(State0, LoadFiles) of
        {ok, State} ->
            process_flag(trap_exit, true),
            {ok, #{state => State, active => 0, limit => ?MAX_REQUESTS,
                    monitors => #{}}};
        {error, Err} -> {stop, Err}
    end.

load_files(State, []) -> {ok, State};
load_files(State, [Path | Rest]) ->
    case gleamunison@mcp_session:load_file(State, Path) of
        {ok, State2} -> load_files(State2, Rest);
        {error, Err} -> {error, Err}
    end.

handle_call(readiness, _From, Data) -> {reply, true, Data};
handle_call({rpc, Body}, From, #{state := State, active := Active, limit := Limit} = Data)
  when is_binary(Body), Active < Limit ->
    {Pid, Monitor} = spawn_monitor(fun() ->
        Reply = gleamunison@mcp_session:handle_rpc(State, Body),
        gen_server:reply(From, {ok, Reply})
    end),
    {noreply, Data#{active := Active + 1,
                    monitors := maps:put(Monitor, Pid, maps:get(monitors, Data))}};
handle_call({rpc, _Body}, _From, Data) ->
    {reply, {error, busy}, Data};
handle_call(stop, _From, Data) -> {stop, normal, ok, Data};
handle_call(_Request, _From, Data) -> {reply, {error, unsupported}, Data}.

handle_cast(_, Data) -> {noreply, Data}.

handle_info({'DOWN', Monitor, process, _Pid, _Reason},
            #{active := Active, monitors := Monitors} = Data)
  when Active > 0 ->
    {noreply, Data#{active := Active - 1, monitors := maps:remove(Monitor, Monitors)}};
handle_info(_, Data) -> {noreply, Data}.

terminate(_, #{monitors := Monitors}) ->
    maps:foreach(fun(_Monitor, Pid) -> exit(Pid, shutdown) end, Monitors),
    persistent_term:erase({gleamunison_mcp, state}),
    ok;
terminate(_, _) ->
    persistent_term:erase({gleamunison_mcp, state}),
    ok.
