-module(gleamunison_crypto).
-export([hash/2, hmac/3, random_bytes/1, hash_to_hex/1]).
-export([blake2b/2, argon2id/8, argon2_h0/8, secure_compare/2]).

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

blake2b(Data, OutLen) when is_binary(Data), is_integer(OutLen),
                           OutLen >= 1, OutLen =< 64 ->
    {ok, gleamunison_blake2b:hash(Data, OutLen)};
blake2b(_, _) ->
    {error, <<"digest length must be 1..64 bytes">>}.

argon2id(P, S, K, X, Passes, MemKiB, Par, TagLen) ->
    case gleamunison_argon2:hash(P, S, K, X, Passes, MemKiB, Par, TagLen) of
        {error, Reason} -> {error, Reason};
        Tag when is_binary(Tag) -> {ok, Tag}
    end.

%% Test support: exposes the H0 pre-hashing digest for RFC 9106 section 5.3
%% cross-checks. Never call on production password material.
argon2_h0(P, S, K, X, Passes, MemKiB, Par, TagLen) ->
    gleamunison_argon2:h0(P, S, K, X, Passes, MemKiB, Par, TagLen).

secure_compare(A, B) when is_binary(A), is_binary(B),
                          byte_size(A) =:= byte_size(B) ->
    crypto:hash_equals(A, B);
secure_compare(_, _) ->
    false.
