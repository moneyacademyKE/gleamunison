%% One supervised owner for durable application data. The journal is separate
%% from the definition CAS and is committed with one DETS insert and sync.
-module(gleamunison_app_db).
-behaviour(gen_server).
-export([start_link/0, transact/2, get/2, find/2, raise/1, with_path/2,
         stop/0, application_path/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(PATH_KEY, {gleamunison, application_db_path}).
-define(TIMEOUT, 15000).

start_link() -> gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

transact(Assertions, Retractions) -> request({transact, Assertions, Retractions}).
get(Entity, Attribute) when is_binary(Entity), is_binary(Attribute) ->
    request({get, Entity, Attribute});
get(_, _) -> {error, <<"get entity and attribute must be text">>}.
find(Attribute, Value) when is_binary(Attribute), is_binary(Value) ->
    request({find, Attribute, Value});
find(_, _) -> {error, <<"find attribute and value must be text">>}.

raise(Reason) -> erlang:error({db_failed, Reason}).

%% Test/embedded embedding scope. Production resolves the path from the same
%% store context as the CLI; this helper never changes that default globally.
with_path(Path, Fun) when is_binary(Path), is_function(Fun, 0) ->
    Old = persistent_term:get(?PATH_KEY, undefined),
    _ = stop(),
    persistent_term:put(?PATH_KEY, Path),
    try Fun()
    after
        _ = stop(),
        case Old of
            undefined -> persistent_term:erase(?PATH_KEY);
            _ -> persistent_term:put(?PATH_KEY, Old)
        end
    end.

stop() -> gleamunison_runtime_sup:stop_db().

application_path() -> configured_path().

request(Message) ->
    case ensure_started() of
        {ok, _} ->
            try gen_server:call(?SERVER, Message, ?TIMEOUT)
            catch exit:Reason -> {error, describe(Reason)}
            end;
        Error -> Error
    end.

ensure_started() ->
    case whereis(?SERVER) of
        Pid when is_pid(Pid) -> {ok, Pid};
        undefined ->
            case gleamunison_runtime_sup:start_db() of
                {ok, Pid} -> {ok, Pid};
                {error, Reason} -> {error, describe(Reason)}
            end
    end.

init([]) ->
    process_flag(trap_exit, true),
    Path = configured_path(),
    case filelib:ensure_dir(binary_to_list(Path)) of
        ok ->
            Name = table_name(Path),
            case dets:open_file(Name, [{file, binary_to_list(Path)}, {type, set}]) of
                {ok, Name} ->
                    try
                        Facts = gleamunison_app_db_facts:replay(Name),
                        NextTx = gleamunison_app_db_facts:next_tx(Name),
                        {ok, #{tab => Name, path => Path, facts => Facts, next_tx => NextTx}}
                    catch
                        Class:Reason -> {stop, describe({Class, Reason})}
                    end;
                {error, Reason} -> {stop, describe(Reason)}
            end;
        {error, Reason} -> {stop, describe(Reason)}
    end.

configured_path() ->
    case persistent_term:get(?PATH_KEY, undefined) of
        Path when is_binary(Path) -> Path;
        undefined ->
            case gleamunison@cli_lifecycle:resolve_context(none) of
                {ok, Context} ->
                    Root = gleamunison@cli_lifecycle:root_dir(Context),
                    filename:join(Root, <<"application.dets">>);
                {error, Reason} -> erlang:error({db_path, Reason})
            end
    end.

%% Table naming is owned by gleamunison_table_name (bk-0249); this site has
%% always produced gleamunison_app_db_<16 uppercase hex chars>.
table_name(Path) ->
    gleamunison_table_name:stable(<<"gleamunison_app_db_">>, Path, 16, uppercase).

handle_call({transact, Assertions, Retractions}, _From, State) ->
    case gleamunison_app_db_facts:validate_changes(Assertions, Retractions) of
        {error, Reason} -> {reply, {error, Reason}, State};
        {ok, nil} -> commit(Assertions, Retractions, State)
    end;
handle_call({get, Entity, Attribute}, _From, State) ->
    Facts = maps:get(facts, State),
    {reply, {ok, gleamunison_app_db_facts:get(Facts, Entity, Attribute)}, State};
handle_call({find, Attribute, Value}, _From, State) ->
    Facts = maps:get(facts, State),
    {reply, {ok, gleamunison_app_db_facts:find(Facts, Attribute, Value)}, State};
handle_call(_, _From, State) -> {reply, {error, <<"unsupported_db_request">>}, State}.

commit(Assertions, Retractions, State) ->
    Tab = maps:get(tab, State),
    Tx = maps:get(next_tx, State),
    Record = {{transaction, Tx}, {Assertions, Retractions}},
    case dets:insert(Tab, Record) of
        ok ->
            case dets:sync(Tab) of
                ok ->
                    Facts = gleamunison_app_db_facts:apply_transaction(
                        maps:get(facts, State), Assertions, Retractions),
                    {reply, {ok, Tx}, State#{facts => Facts, next_tx => Tx + 1}};
                {error, Reason} -> {reply, {error, describe(Reason)}, State}
            end;
        {error, Reason} -> {reply, {error, describe(Reason)}, State}
    end.

handle_cast(_, State) -> {noreply, State}.
handle_info(_, State) -> {noreply, State}.

terminate(_Reason, #{tab := Tab}) ->
    _ = try dets:sync(Tab) catch _:_ -> ok end,
    _ = try dets:close(Tab) catch _:_ -> ok end,
    ok;
terminate(_, _) -> ok.

describe(Term) when is_binary(Term) -> Term;
describe(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
