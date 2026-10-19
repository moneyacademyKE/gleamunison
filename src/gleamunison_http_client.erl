-module(gleamunison_http_client).
-export([request/4, request_with_options/6, get/1, post/2, put/2, delete/1]).

request(Method, Url, Headers, Body) ->
    request_with_options(Method, Url, Headers, Body, 180000, none).

request_with_options(Method, Url, Headers, Body, TimeoutMs, Cancellation)
    when is_binary(Method), is_binary(Url), is_integer(TimeoutMs),
         TimeoutMs > 0, TimeoutMs =< 180000 ->
    %% httpc lives in the inets application and HTTPS needs ssl; neither is
    %% auto-started in escript/`gleam run` mode. Idempotent when running.
    application:ensure_all_started(ssl),
    application:ensure_all_started(inets),
    MethodAtom = method_atom(Method),
    UrlString = binary_to_list(Url),
    HeaderList0 = lists:map(fun({K,V}) -> {binary_to_list(K), binary_to_list(V)} end, Headers),
    {ContentType, HeaderList} = take_content_type(HeaderList0),
    Request = case MethodAtom of
        get -> {UrlString, HeaderList};
        delete -> {UrlString, HeaderList};
        _ -> {UrlString, HeaderList, ContentType, Body}
    end,
    case cancelled(Cancellation) of
        true -> {error, <<"request_cancelled">>};
        false -> request_httpc(MethodAtom, Request, TimeoutMs, Cancellation)
    end;
request_with_options(_, _, _, _, _, _) ->
    {error, <<"request_timeout_invalid">>}.

request_httpc(Method, Request, TimeoutMs, Cancellation) ->
    Result = httpc:request(Method, Request,
        [{timeout, TimeoutMs}, {connect_timeout, TimeoutMs}],
        [{sync, false}, {max_body_size, 8 * 1024 * 1024}]),
    case Result of
        {ok, RequestId} ->
            Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
            wait_for_response(RequestId, Deadline, Cancellation);
        {error, Reason} ->
            {error, error_binary(Reason)}
    end.

wait_for_response(RequestId, Deadline, Cancellation) ->
    case cancelled(Cancellation) of
        true -> cancel_request(RequestId, <<"request_cancelled">>);
        false ->
            Remaining = Deadline - erlang:monotonic_time(millisecond),
            case Remaining =< 0 of
                true -> cancel_request(RequestId, <<"request_timeout">>);
                false ->
                    receive
                        {http, {RequestId, {{_Ver, Status, _Reason}, RespHeaders, RespBody}}} ->
                            BinHeaders = [{list_to_binary(K), list_to_binary(V)} || {K, V} <- RespHeaders],
                            {ok, {Status, BinHeaders, RespBody}};
                        {http, {RequestId, {error, Reason}}} ->
                            {error, error_binary(Reason)}
                    after
                        erlang:min(Remaining, 50) ->
                            wait_for_response(RequestId, Deadline, Cancellation)
                    end
            end
    end.

cancel_request(RequestId, Reason) ->
    _ = catch httpc:cancel_request(RequestId),
    {error, Reason}.

cancelled(none) -> false;
cancelled({some, Token}) -> gleamunison_cancellation:cancelled(Token).

error_binary(timeout) -> <<"request_timeout">>;
error_binary({failed_connect, _}) -> <<"connect_failed">>;
error_binary(Reason) -> list_to_binary(io_lib:format("~p", [Reason])).

method_atom(<<"GET">>) -> get;
method_atom(<<"POST">>) -> post;
method_atom(<<"PUT">>) -> put;
method_atom(<<"DELETE">>) -> delete.

%% httpc takes Content-Type as a separate request tuple element, so a
%% "content-type" entry in Headers must be lifted out (case-insensitive);
%% absent, the historical octet-stream default is preserved.
take_content_type(Headers) ->
    case lists:partition(
        fun({K, _}) -> string:lowercase(K) =:= "content-type" end, Headers
    ) of
        {[{_, V} | _], Rest} -> {V, Rest};
        {[], _} -> {"application/octet-stream", Headers}
    end.

get(Url) when is_binary(Url) ->
    request(<<"GET">>, Url, [], <<>>).

post(Url, Body) when is_binary(Url), is_binary(Body) ->
    request(<<"POST">>, Url, [], Body).

put(Url, Body) when is_binary(Url), is_binary(Body) ->
    request(<<"PUT">>, Url, [], Body).

delete(Url) when is_binary(Url) ->
    request(<<"DELETE">>, Url, [], <<>>).
