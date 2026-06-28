-module(gleamunison_crypto).
-export([hash/2, hmac/3, random_bytes/1, hash_to_hex/1]).

hash(Algo, Data) when is_binary(Data) ->
    try
        {ok, crypto:hash(string_to_algo(Algo), Data)}
    catch
        error:_ -> {error, <<"hash failed">>}
    end.

hmac(Algo, Key, Data) when is_binary(Key), is_binary(Data) ->
    try
        {ok, crypto:mac(hmac, string_to_algo(Algo), Key, Data)}
    catch
        error:_ -> {error, <<"hmac failed">>}
    end.

random_bytes(N) when is_integer(N), N > 0 ->
    crypto:strong_rand_bytes(N);
random_bytes(_) ->
    <<>>.

hash_to_hex(Bytes) when is_binary(Bytes) ->
    list_to_binary([io_lib:format("~2.16.0b", [X]) || <<X>> <= Bytes]).

string_to_algo(<<"sha256">>) -> sha256;
string_to_algo(<<"sha512">>) -> sha512;
string_to_algo(<<"md5">>) -> md5;
string_to_algo("sha256") -> sha256;
string_to_algo("sha512") -> sha512;
string_to_algo("md5") -> md5;
string_to_algo(_) -> sha256.
