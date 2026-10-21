-module(gleamunison_llm_budget).
-behaviour(gen_server).
-export([start_link/0, ensure_started/0, admit/2, release/1, spend/3, report_success/1,
         report_failure/1, snapshot/0, reset/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% One row per provider, capped: providers are a configured set, never a
%% user-controlled cardinality. In-flight slots are monitor-backed so a
%% killed caller can never leak the gauge.
-define(MAX_PROVIDERS, 16).

-record(row, {tokens = 0, cost = 0, window_start = 0,
              circuit = closed, opened_at = 0, failures = 0,
              in_flight = 0}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

ensure_started() ->
    case whereis(?MODULE) of
        undefined ->
            case start_link() of
                {ok, Pid} -> unlink(Pid), ok;
                {error, {already_started, _}} -> ok
            end;
        _ -> ok
    end.

admit(Provider, Model) when is_binary(Provider), is_binary(Model) ->
    ensure_started(),
    gen_server:call(?MODULE, {admit, Provider, Model, self()}, 5000).

%% Exactly-once against the death monitor: a normal release demonitors and
%% decrements; if the caller died first, DOWN already did it and this is
%% a no-op.
release(Provider) ->
    ensure_started(),
    gen_server:call(?MODULE, {release, Provider, self()}, 5000).

spend(Provider, Tokens, CostMicro) ->
    ensure_started(),
    gen_server:call(?MODULE, {spend, Provider, Tokens, CostMicro}, 5000).

report_success(Provider) ->
    ensure_started(), gen_server:call(?MODULE, {report_success, Provider}, 5000).

report_failure(Provider) ->
    ensure_started(), gen_server:call(?MODULE, {report_failure, Provider}, 5000).

snapshot() ->
    ensure_started(), gen_server:call(?MODULE, snapshot, 5000).

reset() ->
    ensure_started(), gen_server:call(?MODULE, reset, 5000).

init([]) -> {ok, #{rows => #{}, monitors => #{}}}.

handle_call({admit, Provider, Model, Caller}, _From, State) ->
    #{rows := Rows, monitors := Mons} = State,
    case maps:is_key(Provider, Rows) orelse map_size(Rows) < ?MAX_PROVIDERS of
        false -> {reply, {error, <<"provider_cap_reached">>}, State};
        true ->
            Row0 = maps:get(Provider, Rows, #row{}),
            Now = erlang:system_time(millisecond),
            Budget = budget_from_env(),
            Row1 = roll_window(Row0, Budget, Now),
            Usage = usage_tuple(Row1),
            Circuit = circuit_tuple(Row1),
            case gleamunison@llm_budget:admit(Budget, Usage, Circuit, Model, Now) of
                {ok, nil} ->
                    Mon = erlang:monitor(process, Caller),
                    Row2 = Row1#row{in_flight = Row1#row.in_flight + 1,
                                    window_start = actual_window_start(Row1, Budget, Now)},
                    Row3 = case Row1#row.circuit of
                        open -> Row2#row{circuit = half_open};
                        _ -> Row2
                    end,
                    {reply, {ok, nil}, State#{rows := Rows#{Provider => Row3},
                                       monitors := Mons#{Mon => {Provider, Caller}}}};
                {error, Refusal} ->
                    {reply, {error, gleamunison@llm_budget:refusal_name(Refusal)}, State}
            end
    end;
handle_call({release, Provider, Caller}, _From, State) ->
    #{rows := Rows, monitors := Mons} = State,
    case find_monitor(Mons, Provider, Caller) of
        none -> {reply, {ok, nil}, State};
        {ok, Mon} ->
            erlang:demonitor(Mon, [flush]),
            NewState = update_row(
                State#{monitors := maps:remove(Mon, Mons)},
                Provider, fun(R) -> R#row{in_flight = max(0, R#row.in_flight - 1)} end),
            {reply, {ok, nil}, NewState}
    end;
handle_call({spend, Provider, Tokens, Cost}, _From, State) ->
    #{rows := Rows} = State,
    case maps:find(Provider, Rows) of
        error -> {reply, {ok, nil}, State};
        {ok, Row} ->
            Now = erlang:system_time(millisecond),
            Budget = budget_from_env(),
            Rolled = roll_window(Row, Budget, Now),
            New = Rolled#row{tokens = Rolled#row.tokens + Tokens,
                             cost = Rolled#row.cost + Cost,
                             window_start = actual_window_start(Rolled, Budget, Now)},
            {reply, {ok, nil}, State#{rows := Rows#{Provider => New}}}
    end;
handle_call({report_success, Provider}, _From, State) ->
    {reply, {ok, nil}, update_row(State, Provider,
        fun(R) -> R#row{circuit = closed, failures = 0} end)};
handle_call({report_failure, Provider}, _From, State) ->
    Threshold = env_int("GLEAMUNISON_LLM_CIRCUIT_FAILURE_THRESHOLD", 3),
    Now = erlang:system_time(millisecond),
    {reply, {ok, nil}, update_row(State, Provider, fun(R) ->
        Failures = R#row.failures + 1,
        case gleamunison@llm_budget:after_failure(
                 circuit_tuple(R), Failures, Threshold, Now) of
            {open, T} -> R#row{circuit = open, opened_at = T, failures = Failures};
            _ -> R#row{circuit = closed, failures = Failures}
        end
    end)};
handle_call(snapshot, _From, State) ->
    #{rows := Rows} = State,
    Snap = maps:map(fun(_P, R) ->
        #{tokens => R#row.tokens, cost_micro_usd => R#row.cost,
          in_flight => R#row.in_flight, circuit => R#row.circuit,
          consecutive_failures => R#row.failures}
    end, Rows),
    {reply, Snap, State};
handle_call(reset, _From, State) ->
    #{monitors := Mons} = State,
    maps:foreach(fun(Mon, _) -> erlang:demonitor(Mon, [flush]) end, Mons),
    {reply, {ok, nil}, #{rows => #{}, monitors => #{}}};
handle_call(_Request, _From, State) -> {reply, {error, unknown_call}, State}.

handle_cast(_, State) -> {noreply, State}.

handle_info({'DOWN', Mon, process, _Pid, _}, #{monitors := Mons} = State) ->
    case maps:find(Mon, Mons) of
        error -> {noreply, State};
        {ok, {Provider, _Pid}} ->
            {noreply, update_row(State#{monitors := maps:remove(Mon, Mons)},
                Provider, fun(R) -> R#row{in_flight = max(0, R#row.in_flight - 1)} end)}
    end;
handle_info(_, State) -> {noreply, State}.

find_monitor(Mons, Provider, Pid) ->
    maps:fold(fun
        (Mon, {P, Pid0}, none) when P =:= Provider, Pid0 =:= Pid -> {ok, Mon};
        (_, _, Acc) -> Acc
    end, none, Mons).

update_row(State, Provider, Fun) ->
    #{rows := Rows} = State,
    case maps:find(Provider, Rows) of
        error -> State;
        {ok, Row} -> State#{rows := Rows#{Provider => Fun(Row)}}
    end.

roll_window(Row, Budget, Now) ->
    case effective(Row, Budget, Now) of
        rolled -> Row#row{tokens = 0, cost = 0, window_start = Now};
        current -> Row
    end.

effective(Row, Budget, Now) ->
    WindowMs = element(5, Budget),
    case Row#row.window_start of
        0 -> current;
        Start when Now - Start >= WindowMs -> rolled;
        _ -> current
    end.

actual_window_start(Row, Budget, Now) ->
    case effective(Row, Budget, Now) of
        rolled -> Now;
        current -> Row#row.window_start
    end.

usage_tuple(Row) ->
    {usage, Row#row.tokens, Row#row.cost, Row#row.in_flight,
     case Row#row.window_start of
         0 -> erlang:system_time(millisecond);
         S -> S
     end}.

circuit_tuple(#row{circuit = open, opened_at = T}) -> {open, T};
circuit_tuple(#row{circuit = half_open}) -> half_open;
circuit_tuple(_) -> closed.

budget_from_env() ->
    Models = case os:getenv("GLEAMUNISON_LLM_ALLOWED_MODELS") of
        false -> [];
        "" -> [];
        Csv -> [list_to_binary(string:trim(M)) || M <- string:split(Csv, ",", all)]
    end,
    {budget,
     env_int("GLEAMUNISON_LLM_MAX_TOKENS", 1000000),
     env_int("GLEAMUNISON_LLM_MAX_COST_MICRO_USD", 10000000),
     env_int("GLEAMUNISON_LLM_MAX_CONCURRENT", 4),
     env_int("GLEAMUNISON_LLM_WINDOW_MS", 3600000),
     Models,
     env_int("GLEAMUNISON_LLM_CIRCUIT_FAILURE_THRESHOLD", 3),
     env_int("GLEAMUNISON_LLM_CIRCUIT_RESET_MS", 30000)}.

env_int(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Value ->
            try list_to_integer(Value) of
                N when N > 0 -> N
            catch _:_ -> Default end
    end.
