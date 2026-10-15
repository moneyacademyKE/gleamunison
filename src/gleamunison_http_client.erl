-module(gleamunison_http_client).
-export([request/4, get/1, post/2, put/2, delete/1]).

request(Method, Url, Headers, Body) when is_binary(Method), is_binary(Url) ->
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
    case httpc:request(MethodAtom, Request, [{timeout, 180000}, {connect_timeout, 30000}], [{body_format, binary}]) of
        {ok, {{_Ver, Status, _Reason}, RespHeaders, RespBody}} ->
            BinHeaders = [{list_to_binary(K), list_to_binary(V)} || {K, V} <- RespHeaders],
            {ok, {Status, BinHeaders, RespBody}};
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

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
