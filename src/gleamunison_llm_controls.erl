-module(gleamunison_llm_controls).
-export([safe_url/1]).

safe_url(Url) when is_binary(Url), byte_size(Url) =< 2048 ->
    try
        #{scheme := Scheme, host := Host} = Parts = uri_string:parse(Url),
        false = maps:is_key(userinfo, Parts),
        false = maps:is_key(query, Parts),
        false = maps:is_key(fragment, Parts),
        true = binary:match(Url, [<<"\r">>, <<"\n">>, <<0>>]) =:= nomatch,
        true = byte_size(Host) > 0,
        Scheme =:= <<"https">> orelse
            (Scheme =:= <<"http">> andalso lists:member(Host, [<<"localhost">>, <<"127.0.0.1">>, <<"::1">>]))
    catch _:_ -> false
    end;
safe_url(_) -> false.
