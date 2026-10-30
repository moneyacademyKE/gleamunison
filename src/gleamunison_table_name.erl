-module(gleamunison_table_name).
-export([stable/4]).

%% One owner for "binary material -> stable small atom" table naming used by
%% the DETS and Mnesia sites (bk-0249). The hash-encode-truncate-atom dance
%% was previously triplicated across gleamunison_app_db, gleamunison_store_log
%% and gleamunison_storage, with two divergent hex encoders (uppercase
%% binary:encode_hex vs lowercase gleamunison_ffi:hash_to_hex) and divergent
%% input handling.
%%
%% The atom names are load-bearing on disk: Mnesia persists table names in
%% its schema and DETS/Mnesia files were opened under these names, so each
%% site pins the exact output shape it has always produced — prefix, hex
%% length, hex case — and this function must keep those bytes identical
%% (golden atoms are regression-tested in test/table_name_test.gleam).
%%
%% Callers normalize their own input before calling (e.g. store_log converts
%% possibly-charlist paths with unicode:characters_to_binary/1); this module
%% hashes exactly the binary it is given.
stable(Prefix, Material, HexChars, Case)
        when is_binary(Prefix), is_binary(Material),
             is_integer(HexChars), HexChars > 0, HexChars =< 64,
             (Case =:= uppercase orelse Case =:= lowercase) ->
    Hex = hex(crypto:hash(sha256, Material), Case),
    binary_to_atom(<<Prefix/binary, (binary:part(Hex, 0, HexChars))/binary>>, utf8).

hex(Digest, uppercase) -> binary:encode_hex(Digest);
hex(Digest, lowercase) -> iolist_to_binary(gleamunison_ffi:hash_to_hex(Digest)).
