-module(gleamunison_runtime_sup).
-behaviour(supervisor).
-export([start_link/0, init/1, start_http/1, start_mcp/1, stop_http/0,
         stop_mcp/0, stop/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Flags = #{strategy => one_for_one, intensity => 3, period => 5},
    {ok, {Flags, []}}.

start_http(Port) when is_integer(Port) ->
    case ensure_started() of
        {ok, Sup} -> start_child(Sup, http, gleamunison_http_sup,
                                 start_link, [Port], supervisor, infinity);
        Error -> Error
    end.

start_mcp(LoadFiles) when is_list(LoadFiles) ->
    case ensure_started() of
        {ok, Sup} -> start_child(Sup, mcp, gleamunison_mcp_session,
                                 start_link, [LoadFiles], worker, 5000);
        Error -> Error
    end.

stop_http() ->
    Result = stop_child(http),
    case Result of
        ok -> persistent_term:erase({gleamunison_http, listener});
        _ -> ok
    end,
    Result.
stop_mcp() -> stop_child(mcp).

stop() ->
    case whereis(?MODULE) of
        undefined -> ok;
        Pid ->
            Ref = erlang:monitor(process, Pid),
            exit(Pid, shutdown),
            receive
                {'DOWN', Ref, process, Pid, _} -> ok
            after 5000 -> timeout
            end
    end.

ensure_started() ->
    case whereis(?MODULE) of
        Pid when is_pid(Pid) -> {ok, Pid};
        undefined ->
            case start_link() of
                {ok, Pid} -> unlink(Pid), {ok, Pid};
                {error, {already_started, Pid}} -> {ok, Pid};
                {error, Reason} -> {error, Reason}
            end
    end.

start_child(Sup, Id, Module, Function, Args, Type, Shutdown) ->
    Spec = #{id => Id, start => {Module, Function, Args},
             restart => permanent, shutdown => Shutdown,
             type => Type, modules => [Module]},
    case supervisor:start_child(Sup, Spec) of
        {ok, Pid} -> {ok, Pid};
        {ok, Pid, _Info} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid};
        {error, already_present} ->
            case supervisor:restart_child(Sup, Id) of
                {ok, Pid} -> {ok, Pid};
                {ok, Pid, _Info} -> {ok, Pid};
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} -> {error, Reason}
    end.

stop_child(Id) ->
    case whereis(?MODULE) of
        undefined -> ok;
        Sup ->
            case supervisor:terminate_child(Sup, Id) of
                ok -> delete_child(Sup, Id);
                {error, not_found} -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.

delete_child(Sup, Id) ->
    case supervisor:delete_child(Sup, Id) of
        ok -> ok;
        {error, not_found} -> ok;
        {error, Reason} -> {error, Reason}
    end.
