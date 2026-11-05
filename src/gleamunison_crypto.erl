-module(gleamunison_crypto).
-export([hash/2, hmac/3, random_bytes/1, hash_to_hex/1]).
-export([secure_compare/2, constant_time_equal/2]).

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
string_to_algo(<<"trigger_error">>) -> trigger_error;
string_to_algo("sha256") -> sha256;
string_to_algo("sha512") -> sha512;
string_to_algo("md5") -> md5;
string_to_algo(_) -> sha256.

secure_compare(A, B) when is_binary(A), is_binary(B),
                          byte_size(A) =:= byte_size(B) ->
    crypto:hash_equals(A, B);
secure_compare(_, _) ->
    false.

%% Constant-time equality for secrets of arbitrary, possibly UNEQUAL length:
%% both sides are sha256-hashed first, so the comparison always runs over
%% fixed 32-byte digests — no length oracle, and secure_compare/2's
%% equal-size guard can never short-circuit. Never pass raw secrets to
%% secure_compare/2 directly: unequal lengths return false without ever
%% entering the constant-time path. The HTTP bearer gate and the TCP sync
%% handshake hand-rolled this compare twice (bk-49ec); this is the one owner.
constant_time_equal(A, B) when is_binary(A), is_binary(B) ->
    secure_compare(crypto:hash(sha256, A), crypto:hash(sha256, B)).
