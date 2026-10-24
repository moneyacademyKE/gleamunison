-module(gleamunison_web_session).
-behaviour(gen_server).

%% The live session behind the HTTP `/eval` and `/define` routes.
%%
%% The routes used to call a stateless evaluator: no baseline environment, and
%% no state between requests. So `/eval?expr=(+ 1 2)` answered "undefined
%% variable `+`" and `/define?name=foo&expr=42` recorded the source text in a
%% notebook while binding nothing — the route said "defined" and nothing was.
%%
%% One process owns the session, so a define is visible to the next eval and two
%% concurrent requests cannot interleave their cache updates. The session value
%% itself stays immutable and lives in this process's state; callers get values.

-export([start_link/0, eval/1, define/2, definitions/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(CALL_TIMEOUT, 10000).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% Returns {ok, Value} or {error, Reason}. A crash inside evaluation is caught
%% here so one bad expression cannot take the session down with it.
eval(Source) when is_binary(Source) ->
    call({eval, Source}).

define(Name, Source) when is_binary(Name), is_binary(Source) ->
    call({define, Name, Source}).

%% What the session holds, for /browse. The session is the only owner of what is
%% defined; a second notebook table would be a copy that can disagree.
definitions() ->
    call(definitions).

stop() ->
    case whereis(?SERVER) of
        undefined -> ok;
        _ -> gen_server:call(?SERVER, stop, ?CALL_TIMEOUT)
    end.

%% The session is started once, by the server, under the supervisor. A
%% request handler must never start it: the link would die with the connection,
%% and the next request would get a fresh, empty session — which is exactly what
%% happened when this was lazily started (a define vanished between two curls).
call(Message) ->
    case whereis(?SERVER) of
        undefined -> {error, <<"session not running">>};
        _ -> do_call(Message)
    end.

do_call(Message) ->
    try gen_server:call(?SERVER, Message, ?CALL_TIMEOUT) of
        Reply -> Reply
    catch
        exit:{timeout, _} -> {error, <<"session timeout">>};
        Class:Reason -> {error, describe({Class, Reason})}
    end.

init([]) ->
    process_flag(trap_exit, true),
    {ok, gleamunison@mcp_session:boot()}.

handle_call({eval, Source}, _From, State) ->
    {Reply, Next} = run(State, gleamunison@mcp_session:eval_source(State, Source)),
    {reply, Reply, Next};
handle_call({define, Name, Source}, _From, State) ->
    {Reply, Next} = run(State, gleamunison@mcp_session:define_source(State, Name, Source)),
    {reply, Reply, Next};
handle_call(definitions, _From, State) ->
    {reply, {ok, gleamunison@mcp_session:defined_names(State)}, State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, <<"unsupported">>}, State}.

%% Both session calls answer the same shape: either an advanced state plus the
%% value, or a message. Nothing mutates on error.
run(_State, {ok, {Value, Next}}) ->
    {{ok, Value}, Next};
run(State, {error, Reason}) ->
    {{error, to_binary(Reason)}, State}.

handle_cast(_, State) -> {noreply, State}.

handle_info(_, State) -> {noreply, State}.

terminate(_, _) -> ok.

to_binary(Bin) when is_binary(Bin) -> Bin;
to_binary(List) when is_list(List) -> list_to_binary(List);
to_binary(Other) -> iolist_to_binary(io_lib:format("~tp", [Other])).

describe({Class, Reason}) ->
    iolist_to_binary(io_lib:format("~p:~p", [Class, Reason]));
describe(Other) ->
    to_binary(Other).
