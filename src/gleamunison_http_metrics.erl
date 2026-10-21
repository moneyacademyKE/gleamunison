-module(gleamunison_http_metrics).
-export([begin_request/1, observe/1]).

%% One choke point for request telemetry.
%%
%% Every HTTP response leaves through gleamunison_http_util's three send
%% functions, so that is where a response is counted. The path travels in the
%% process dictionary because a worker handles exactly one request and the
%% send functions are three frames below the router; threading a path through
%% every route signature would add a parameter to twenty handlers to serve a
%% counter.
%%
%% Nothing here may raise: telemetry must never turn a served request into a
%% crashed worker.

-define(COUNTER_TOTAL, <<"http_requests_total">>).
-define(COUNTER_ERRORS, <<"http_errors_total">>).
-define(HISTOGRAM_DURATION, <<"http_request_duration_us">>).
-define(PATH_KEY, gleamunison_http_metrics_path).
-define(START_KEY, gleamunison_http_metrics_start).

begin_request(Path) when is_binary(Path) ->
    put(?PATH_KEY, Path),
    put(?START_KEY, erlang:monotonic_time(microsecond)),
    ok.

observe(Status) when is_integer(Status) ->
    try
        gleamunison_metrics:counter(?COUNTER_TOTAL, 1),
        gleamunison_metrics:histogram(?HISTOGRAM_DURATION, elapsed_us()),
        case Status >= 400 of
            true -> observe_error(Status);
            false -> ok
        end
    catch
        _:_ -> ok
    end.

observe_error(Status) ->
    Path = case get(?PATH_KEY) of
        undefined -> <<"unknown">>;
        P -> P
    end,
    gleamunison_metrics:counter(?COUNTER_ERRORS, 1),
    gleamunison_metrics:counter(<<"http_status_", (integer_to_binary(Status))/binary>>, 1),
    %% The log buffer is what /api/logs serves; an error the operator cannot
    %% see is an error nobody diagnoses.
    gleamunison_log:log_entry(
        <<"error">>,
        <<"http_error ", (integer_to_binary(Status))/binary, " ", Path/binary>>,
        [<<"status">>, <<"path">>],
        [integer_to_binary(Status), Path]
    ).

elapsed_us() ->
    case get(?START_KEY) of
        undefined -> 0;
        Start -> erlang:monotonic_time(microsecond) - Start
    end.
