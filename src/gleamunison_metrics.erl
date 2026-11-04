-module(gleamunison_metrics).
-behaviour(gen_server).
-export([counter/2, gauge/2, histogram/2, list_metrics/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

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

%% State: series => #{{Kind, Name} => Cursor} (one entry per admitted
%% series; the cursor is the histogram ring position, 0 for counters and
%% gauges), rows => #{RowKey => Value} (the flat rows list_metrics/0
%% serves). Every read and write crosses the gen_server boundary, so the
%% single state map is the one authority: there is no second store to
%% drift from it.
init([]) ->
    {ok, #{series => #{}, rows => #{}}}.

handle_call({record, Kind, Name, Value}, _From, #{series := Series, rows := Rows} = State) ->
    Key = {Kind, Name},
    case maps:is_key(Key, Series) orelse maps:size(Series) < ?MAX_SERIES of
        false -> {reply, dropped, State};
        true ->
            Cursor = maps:get(Key, Series, 0),
            {NextCursor, NextRows} = update(Kind, Name, Value, Cursor, Rows),
            {reply, ok, State#{series => Series#{Key => NextCursor}, rows => NextRows}}
    end;
handle_call(list, _From, #{rows := Rows} = State) ->
    {reply, maps:to_list(Rows), State};
handle_call(_Request, _From, State) -> {reply, {error, unknown_call}, State}.

update(counter, Name, Delta, Cursor, Rows) ->
    Row = {counter, Name},
    {Cursor, Rows#{Row => maps:get(Row, Rows, 0) + Delta}};
update(gauge, Name, Value, Cursor, Rows) ->
    {Cursor, Rows#{{gauge, Name} => Value}};
update(histogram, Name, Value, Cursor, Rows) ->
    {(Cursor + 1) rem ?MAX_SAMPLES, Rows#{{histogram, Name, Cursor} => Value}}.

handle_cast(_Message, State) -> {noreply, State}.
handle_info(_Message, State) -> {noreply, State}.
