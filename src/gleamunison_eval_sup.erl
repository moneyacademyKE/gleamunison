-module(gleamunison_eval_sup).
-behaviour(supervisor).
-export([start_scope/4, init/1]).

start_scope(Owner, Token, Fun, Timeout) ->
    case ensure_started() of
        ok -> supervisor:start_child(?MODULE, #{
            id => make_ref(),
            start => {gleamunison_eval_scope, start_link, [Owner, Token, Fun, Timeout]},
            restart => temporary, shutdown => 5000, type => worker,
            modules => [gleamunison_eval_scope]});
        {error, _} = Error -> Error
    end.

ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
            case supervisor:start_link({local, ?MODULE}, ?MODULE, []) of
                {ok, Pid} -> unlink(Pid), ok;
                {error, {already_started, _}} -> ok;
                {error, _} = Error -> Error
            end;
        _ -> ok
    end.

init([]) -> {ok, {#{strategy => one_for_one, intensity => 3, period => 5}, []}}.
