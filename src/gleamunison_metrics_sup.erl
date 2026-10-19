-module(gleamunison_metrics_sup).
-behaviour(supervisor).
-export([ensure_started/0, init/1]).

%% Library callers may be short-lived and need not boot the application
%% supervisor. This tiny root owns only metrics, not listeners or storage.
ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
            case supervisor:start_link({local, ?MODULE}, ?MODULE, []) of
                {ok, Pid} -> unlink(Pid), ok;
                {error, {already_started, _}} -> ok;
                {error, Reason} -> error({metrics_start_failed, Reason})
            end;
        _ -> ok
    end.

init([]) ->
    Child = #{id => metrics, start => {gleamunison_metrics, start_link, []},
              restart => permanent, shutdown => 1000, type => worker,
              modules => [gleamunison_metrics]},
    {ok, {#{strategy => one_for_one, intensity => 3, period => 5}, [Child]}}.
