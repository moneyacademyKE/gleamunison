-module(gleamunison_http_sup).
-behaviour(supervisor).
-export([start_link/1, stop/0, init/1]).

%% Library callers may be short-lived; the supervisor must outlive the caller.
start_link(Port) when is_integer(Port) ->
    case supervisor:start_link({local, ?MODULE}, ?MODULE, [Port]) of
        {ok, Pid} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid};
        {error, Reason} -> {error, Reason}
    end.

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

init([Port]) ->
    Flags = #{strategy => one_for_one, intensity => 3, period => 5},
    Children = case Port > 0 of
        true -> [#{id => http, start => {gleamunison_http, start_link, [Port]},
                   restart => permanent, shutdown => 5000, type => worker,
                   modules => [gleamunison_http]}];
        false -> []
    end,
    {ok, {Flags, Children}}.
