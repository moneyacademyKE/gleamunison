-module(gleamunison_mcp_session).
-behaviour(gen_server).
-define(MAX_REQUESTS, 64).
-export([start_link/1, start/1, stop/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2]).

%% MCP is a bounded gateway, not a second codebase session. Each request reads
%% the current snapshot from the supervised web session, the sole scratch owner.
start(LoadFiles) when is_list(LoadFiles) ->
    case gleamunison_http:ensure_storage() of
        ok ->
            case gleamunison_runtime_sup:start_web_session(LoadFiles) of
                {ok, _Pid} ->
                    case gleamunison_runtime_sup:start_mcp([]) of
                        {ok, _} -> {ok, nil};
                        {error, Reason} -> {error, Reason}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} -> {error, Reason}
    end.

start_link(Ignored) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Ignored, []).

stop() ->
    gleamunison_runtime_sup:stop_mcp(),
    gleamunison_runtime_sup:stop_web_session(),
    nil.

init(_) ->
    process_flag(trap_exit, true),
    {ok, #{active => 0, limit => ?MAX_REQUESTS, monitors => #{}}}.

handle_call(readiness, _From, Data) ->
    Reply = case gleamunison_web_session:snapshot() of
        {ok, _} -> true;
        _ -> false
    end,
    {reply, Reply, Data};
handle_call({rpc, Body}, From, #{active := Active, limit := Limit} = Data)
  when is_binary(Body), Active < Limit ->
    case gleamunison_web_session:snapshot() of
        {ok, State} ->
            {Pid, Monitor} = spawn_monitor(fun() ->
                Reply = gleamunison@mcp_session:handle_rpc(State, Body),
                gen_server:reply(From, {ok, Reply})
            end),
            {noreply, Data#{active := Active + 1,
                            monitors := maps:put(Monitor, Pid, maps:get(monitors, Data))}};
        {error, Reason} -> {reply, {error, Reason}, Data}
    end;
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
    ok;
terminate(_, _) -> ok.
