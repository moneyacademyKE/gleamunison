-module(gleamunison_readiness).
-export([report/0, ready/0, http_response/0]).

%% Readiness observes required resources; it never executes stored code,
%% mutates a branch, scans a codebase, or bootstraps an absent service.
report() ->
    {Services, ConfigOk} = required_services(),
    Base = [
        run(<<"storage">>, true, fun storage_check/0),
        run(<<"version">>, true, fun version_check/0),
        run(<<"schema">>, true, fun schema_check/0),
        run(<<"memory">>, true, fun memory_check/0),
        #{name => <<"configuration">>, required => true, ok => ConfigOk,
          detail => case ConfigOk of true -> <<"valid">>; false -> <<"invalid_required_services">> end}
    ],
    Checks = Base ++ [run(atom_to_binary(Name, utf8), lists:member(Name, Services),
                         fun() -> service_check(Name) end) || Name <- [http, mcp, sync]],
    Ready = lists:all(fun(#{required := Required, ok := Ok}) -> not Required orelse Ok end, Checks),
    #{ready => Ready, status => case Ready of true -> <<"healthy">>; false -> <<"unhealthy">> end,
      version => version(), schema_version => gleamunison_definition_codec:version(),
      checks => Checks}.

ready() -> maps:get(ready, report()).

http_response() ->
    Report = report(),
    Status = case maps:get(ready, Report) of true -> 200; false -> 503 end,
    {Status, iolist_to_binary(json:encode(Report))}.

required_services() ->
    case os:getenv("GLEAMUNISON_REQUIRED_SERVICES") of
        false -> {[], true};
        "" -> {[], true};
        Value when length(Value) =< 128 ->
            Names = [string:trim(N) || N <- string:split(Value, ",", all)],
            Known = [{"http", http}, {"mcp", mcp}, {"sync", sync}],
            {[Atom || {Name, Atom} <- Known, lists:member(Name, Names)],
             lists:all(fun(N) -> lists:keymember(N, 1, Known) end, Names)};
        _ -> {[], false}
    end.

run(Name, Required, Fun) ->
    {Ok, Detail} = bounded(Fun),
    #{name => Name, required => Required, ok => Ok, detail => Detail}.

bounded(Fun) ->
    Parent = self(), Ref = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Result = try Fun() catch _:_ -> {false, <<"check_failed">>} end,
        Parent ! {Ref, Result}
    end),
    receive
        {Ref, Result} -> erlang:demonitor(Monitor, [flush]), Result;
        {'DOWN', Monitor, process, Pid, _} -> {false, <<"check_failed">>}
    after 150 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end,
        receive {Ref, _} -> ok after 0 -> ok end,
        {false, <<"check_timeout">>}
    end.

storage_check() ->
    case persistent_term:get({gleamunison, active_storage}, undefined) of
        {ets, Tab} ->
            _ = ets:lookup(Tab, <<0:256>>), {true, <<"ets_open">>};
        {dets, Tab} ->
            case gleamunison_storage:dets_lookup(Tab, <<0:256>>) of
                {ok, _} -> {true, <<"dets_open">>};
                _ -> {false, <<"storage_unavailable">>}
            end;
        {partitioned_dets, Dir} ->
            %% Directory availability is not a claim of full shard integrity.
            {filelib:is_dir(Dir), <<"partition_directory">>};
        {mnesia, Tab} ->
            case mnesia:system_info(is_running) of
                yes -> {lists:member(Tab, mnesia:system_info(local_tables)), <<"mnesia_table">>};
                _ -> {false, <<"mnesia_unavailable">>}
            end;
        _ -> {false, <<"storage_unavailable">>}
    end.

version() ->
    case application:get_key(gleamunison, vsn) of
        {ok, V} when is_list(V) -> list_to_binary(V);
        {ok, V} when is_binary(V) -> V;
        _ -> <<>>
    end.

version_check() -> {byte_size(version()) > 0, <<"application_manifest">>}.
schema_check() -> {gleamunison_definition_codec:version() =:= 1, <<"definition_codec">>}.

memory_check() ->
    case memory_limit() of
        {ok, Limit} -> {erlang:memory(total) < Limit * 1024 * 1024, <<"memory_limit">>};
        error -> {false, <<"invalid_memory_limit">>}
    end.

memory_limit() ->
    case os:getenv("GLEAMUNISON_MAX_MEMORY_MB") of
        false -> {ok, 4096};
        Value when length(Value) =< 12 ->
            try list_to_integer(Value) of
                N when N > 0, N =< 1048576 -> {ok, N};
                _ -> error
            catch _:_ -> error end;
        _ -> error
    end.

service_check(http) ->
    case persistent_term:get({gleamunison_http, listener}, undefined) of
        {Pid, Socket} when is_pid(Pid) ->
            {is_process_alive(Pid) andalso listener_open(Socket), <<"http_listener">>};
        _ -> {false, <<"http_not_running">>}
    end;
service_check(mcp) ->
    case whereis(gleamunison_mcp_session) of
        undefined -> {false, <<"mcp_not_running">>};
        Pid ->
            case process_info(Pid, status) of
                {status, suspended} -> {false, <<"check_timeout">>};
                _ ->
                    case catch gen_server:call(Pid, readiness, 100) of
                        true -> {true, <<"mcp_responsive">>};
                        _ -> {false, <<"mcp_unavailable">>}
                    end
            end
    end;
service_check(sync) ->
    case whereis(gleamunison_tcp_sync) of
        undefined -> {false, <<"sync_not_running">>};
        Pid ->
            case gen_server:call(Pid, readiness, 100) of
                true -> {true, <<"sync_listener">>};
                _ -> {false, <<"sync_unavailable">>}
            end
    end.

listener_open(Socket) ->
    case inet:sockname(Socket) of {ok, _} -> true; _ -> false end.
