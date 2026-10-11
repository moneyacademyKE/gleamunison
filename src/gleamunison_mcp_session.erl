%% Process holder for the MCP session state. All logic lives in
%% gleamunison@mcp_session (pure Gleam); this module only owns the
%% registered name and the receive loop so per-request handler processes
%% can reach the booted session.
-module(gleamunison_mcp_session).
-export([start/1, stop/0]).

start(LoadFiles) when is_list(LoadFiles) ->
    case whereis(gleamunison_mcp_session) of
        undefined ->
            State0 = gleamunison@mcp_session:boot(),
            case load_files(State0, LoadFiles) of
                {ok, State} ->
                    Pid = spawn(fun() -> loop(State) end),
                    register(gleamunison_mcp_session, Pid),
                    {ok, nil};
                {error, Err} ->
                    {error, Err}
            end;
        _Pid ->
            {error, <<"mcp session already running">>}
    end.

load_files(State, []) -> {ok, State};
load_files(State, [Path | Rest]) ->
    case gleamunison@mcp_session:load_file(State, Path) of
        {ok, State2} -> load_files(State2, Rest);
        {error, Err} -> {error, Err}
    end.

stop() ->
    case whereis(gleamunison_mcp_session) of
        undefined -> nil;
        Pid -> Pid ! stop, nil
    end.

loop(State) ->
    receive
        {rpc, Body, From} ->
            case gleamunison@mcp_session:handle_rpc(State, Body) of
                {respond, Reply} -> From ! {mcp_reply, {ok, Reply}};
                no_reply -> From ! {mcp_reply, no_reply}
            end,
            loop(State);
        stop ->
            ok
    end.
