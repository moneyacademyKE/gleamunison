-module(gleamunison_metrics).
-behaviour(gen_server).
-export([counter/2, gauge/2, histogram/2, list_metrics/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, gleamunison_metrics).
-define(MAX_SERIES, 256).
-define(MAX_SAMPLES, 128).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

counter(Name, Delta) when is_integer(Delta) -> record(counter, Name, Delta).
gauge(Name, Value) when is_number(Value) -> record(gauge, Name, Value).
histogram(Name, Value) when is_number(Value) -> record(histogram, Name, Value).

record(Kind, Name, Value) when is_binary(Name), byte_size(Name) > 0, byte_size(Name) =< 128 ->
    ok = gleamunison_metrics_sup:ensure_started(),
    case gen_server:call(?MODULE, {record, Kind, Name, Value}, 1000) of
        ok ->
            %% Fixed event names: values and labels are measurements/metadata,
            %% never fresh event identifiers on every observation.
            try telemetry:execute([gleamunison, Kind], #{value => Value}, #{name => Name})
            catch _:_ -> ok end;
        dropped -> ok
    end,
    nil;
record(_, _, _) -> nil.

list_metrics() ->
    ok = gleamunison_metrics_sup:ensure_started(),
    gen_server:call(?MODULE, list, 1000).

init([]) ->
    ets:new(?TABLE, [set, protected, named_table]),
    {ok, #{}}.

handle_call({record, Kind, Name, Value}, _From, Series) ->
    Key = {Kind, Name},
    case maps:is_key(Key, Series) orelse map_size(Series) < ?MAX_SERIES of
        false -> {reply, dropped, Series};
        true ->
            Slot = maps:get(Key, Series, 0),
            Next = update(Kind, Name, Value, Slot),
            {reply, ok, Series#{Key => Next}}
    end;
handle_call(list, _From, State) -> {reply, ets:tab2list(?TABLE), State};
handle_call(_Request, _From, State) -> {reply, {error, unknown_call}, State}.

update(counter, Name, Delta, Slot) ->
    ets:update_counter(?TABLE, {counter, Name}, {2, Delta}, {{counter, Name}, 0}), Slot;
update(gauge, Name, Value, Slot) ->
    ets:insert(?TABLE, {{gauge, Name}, Value}), Slot;
update(histogram, Name, Value, Slot) ->
    ets:insert(?TABLE, {{histogram, Name, Slot}, Value}),
    (Slot + 1) rem ?MAX_SAMPLES.

handle_cast(_Message, State) -> {noreply, State}.
handle_info(_Message, State) -> {noreply, State}.
