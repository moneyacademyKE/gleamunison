-module(gleamunison_http_client).
-export([request/4, get/1, post/2, put/2, delete/1]).

request(Method, Url, Headers, Body) when is_binary(Method), is_binary(Url) ->
    MethodAtom = method_atom(Method),
    UrlString = binary_to_list(Url),
    HeaderList = lists:map(fun({K,V}) -> {binary_to_list(K), binary_to_list(V)} end, Headers),
    Request = case MethodAtom of
        get -> {UrlString, HeaderList};
        delete -> {UrlString, HeaderList};
        _ -> {UrlString, HeaderList, "application/octet-stream", Body}
    end,
    case httpc:request(MethodAtom, Request, [], [{body_format, binary}]) of
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

get(Url) when is_binary(Url) ->
    request(<<"GET">>, Url, [], <<>>).

post(Url, Body) when is_binary(Url), is_binary(Body) ->
    request(<<"POST">>, Url, [], Body).

put(Url, Body) when is_binary(Url), is_binary(Body) ->
    request(<<"PUT">>, Url, [], Body).

delete(Url) when is_binary(Url) ->
    request(<<"DELETE">>, Url, [], <<>>).
