-module(gleamunison_web_session).
-behaviour(gen_server).

%% One supervised owner for HTTP scratch and the snapshots MCP reads. Durable
%% branch/CAS entries and mutable source overlays remain distinct in the value.
-export([start_link/0, start_link/1, eval/1, define/2, publish/1, generate/1, definitions/0,
         definition_catalog/0, snapshot/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(CALL_TIMEOUT, 30000).
%% Eight attempts at the provider's 180-second ceiling, plus local admission.
%% The owner stays occupied; the caller must not time out and abandon live work.
-define(GENERATION_TIMEOUT, 1500000).

start_link() -> start_link([]).
start_link(LoadFiles) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, LoadFiles, []).

eval(Source) when is_binary(Source) -> call({eval, Source}).
define(Name, Source) when is_binary(Name), is_binary(Source) ->
    call({define, Name, Source}).
publish(Source) when is_binary(Source) -> call({publish, Source}).
generate(Plan) -> call({generate, Plan}, ?GENERATION_TIMEOUT).
definitions() -> call(definitions).
definition_catalog() -> call(definition_catalog).
snapshot() -> call(snapshot).

stop() ->
    case whereis(?SERVER) of
        undefined -> ok;
        _ -> gen_server:call(?SERVER, stop, ?CALL_TIMEOUT)
    end.

call(Message) -> call(Message, ?CALL_TIMEOUT).

call(Message, Timeout) ->
    case whereis(?SERVER) of
        undefined -> {error, <<"session not running">>};
        _ -> do_call(Message, Timeout)
    end.

do_call(Message, Timeout) ->
    try gen_server:call(?SERVER, Message, Timeout) of
        Reply -> Reply
    catch
        exit:{timeout, _} -> {error, <<"session timeout">>};
        Class:Reason -> {error, describe({Class, Reason})}
    end.

init(LoadFiles) ->
    process_flag(trap_exit, true),
    case gleamunison@mcp_session:boot_configured() of
        {ok, State} ->
            case load_files(State, LoadFiles) of
                {ok, Loaded} -> {ok, Loaded};
                {error, Reason} -> {stop, Reason}
            end;
        {error, Reason} -> {stop, Reason}
    end.

load_files(State, []) -> {ok, State};
load_files(State, [Path | Rest]) ->
    case gleamunison@mcp_session:load_file(State, Path) of
        {ok, Next} -> load_files(Next, Rest);
        {error, Reason} -> {error, Reason}
    end.

handle_call({eval, Source}, _From, State) ->
    {Reply, Next} = run(State, gleamunison@mcp_session:eval_source(State, Source)),
    {reply, Reply, Next};
handle_call({define, Name, Source}, _From, State) ->
    {Reply, Next} = run(State, gleamunison@mcp_session:define_source(State, Name, Source)),
    {reply, Reply, Next};
handle_call({publish, Source}, _From, State) ->
    {Reply, Next} = run(State, gleamunison@session_refresh:publish(State, Source)),
    {reply, Reply, Next};
handle_call({generate, Plan}, _From, State) ->
    {Reply, Next} = run(State, gleamunison@session_refresh:generate(State, Plan)),
    {reply, Reply, Next};
handle_call(definitions, _From, State) ->
    {reply, {ok, gleamunison@mcp_session:defined_names(State)}, State};
handle_call(definition_catalog, _From, State) ->
    {reply, {ok, gleamunison@mcp_session:definitions_json(State)}, State};
handle_call(snapshot, _From, State) ->
    {reply, {ok, State}, State};
handle_call(stop, _From, State) -> {stop, normal, ok, State};
handle_call(_Request, _From, State) -> {reply, {error, <<"unsupported">>}, State}.

run(_State, {ok, {Value, Next}}) -> {{ok, Value}, Next};
run(State, {error, Reason}) -> {{error, to_binary(Reason)}, State}.
handle_cast(_, State) -> {noreply, State}.
handle_info(_, State) -> {noreply, State}.
terminate(_, _) -> ok.

to_binary(Bin) when is_binary(Bin) -> Bin;
to_binary(List) when is_list(List) -> list_to_binary(List);
to_binary(Other) -> iolist_to_binary(io_lib:format("~tp", [Other])).
describe({Class, Reason}) ->
    iolist_to_binary(io_lib:format("~p:~p", [Class, Reason]));
describe(Other) -> to_binary(Other).
