%% Pure-Erlang BLAKE2b with parameterizable digest length (RFC 7693).
%% OTP's crypto only offers the fixed 64-byte digest; Argon2's H' needs
%% arbitrary lengths. Verified against RFC 7693 Appendix A and OTP.
-module(gleamunison_blake2b).
-export([hash/2]).

-define(M64, 16#FFFFFFFFFFFFFFFF).
-define(BLOCK, 128).

-define(IV0, 16#6a09e667f3bcc908).
-define(IV1, 16#bb67ae8584caa73b).
-define(IV2, 16#3c6ef372fe94f82b).
-define(IV3, 16#a54ff53a5f1d36f1).
-define(IV4, 16#510e527fade682d1).
-define(IV5, 16#9b05688c2b3e6c1f).
-define(IV6, 16#1f83d9abfb41bd6b).
-define(IV7, 16#5be0cd19137e2179).

-define(IV_TUPLE, {
    ?IV0, ?IV1, ?IV2, ?IV3, ?IV4, ?IV5, ?IV6, ?IV7
}).

%% Message schedule (RFC 7693 section 2.7); rounds 10-11 reuse rows 0-1.
-define(SIGMA, {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
    {11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
    {7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
    {9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
    {2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
    {12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
    {13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
    {6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
    {10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0}
}).

hash(Data, OutLen) when is_binary(Data), OutLen >= 1, OutLen =< 64 ->
    ParamWord = 16#01010000 bor OutLen,
    H0 = list_to_tuple([?IV0 bxor ParamWord, ?IV1, ?IV2, ?IV3, ?IV4, ?IV5,
                        ?IV6, ?IV7]),
    TotalLen = byte_size(Data),
    H = compress_blocks(Data, 0, TotalLen, H0),
    Words = tuple_to_list(H),
    Digest = iolist_to_binary([<<W:64/little>> || W <- Words]),
    binary:part(Digest, 0, OutLen).

compress_blocks(Data, Offset, TotalLen, H) ->
    case TotalLen - Offset of
        0 when TotalLen =:= 0 ->
            %% Empty message: one all-zero final block, t = 0.
            compress_final(H, <<0:?BLOCK/unit:8>>, 0);
        Remaining ->
            BlockLen = min(Remaining, ?BLOCK),
            Block = binary:part(Data, Offset, BlockLen),
            IsLast = Offset + BlockLen =:= TotalLen,
            T = Offset + BlockLen,
            case IsLast of
                true ->
                    Padded = pad_block(Block),
                    compress_final(H, Padded, T);
                false ->
                    H2 = compress(H, Block, T, false),
                    compress_blocks(Data, Offset + BlockLen, TotalLen, H2)
            end
    end.

compress_final(H, PaddedBlock, T) ->
    compress(H, PaddedBlock, T, true).

pad_block(Block) ->
    PadLen = ?BLOCK - byte_size(Block),
    <<Block/binary, 0:PadLen/unit:8>>.

compress(H, Block, T, IsLast) ->
    M = words_of(Block),
    V0 = list_to_tuple(tuple_to_list(H) ++ tuple_to_list(?IV_TUPLE)),
    V1 = setelement(13, V0, element(13, V0) bxor (T band ?M64)),
    V2 = setelement(14, V1, element(14, V1) bxor ((T bsr 64) band ?M64)),
    V = case IsLast of
        true -> setelement(15, V2, element(15, V2) bxor ?M64);
        false -> V2
    end,
    VF = rounds(V, M, 0),
    list_to_tuple([
        element(I, H) bxor element(I, VF) bxor element(I + 8, VF)
        || I <- lists:seq(1, 8)
    ]).

words_of(Block) ->
    list_to_tuple([W || <<W:64/little>> <= Block]).

rounds(V, _M, 12) -> V;
rounds(V, M, R) ->
    Sigma = element(R rem 10 + 1, ?SIGMA),
    rounds(round(V, M, Sigma), M, R + 1).

round(V0, M, S) ->
    V1 = g(V0, M, S, 1, 5, 9, 13, 1, 2),
    V2 = g(V1, M, S, 2, 6, 10, 14, 3, 4),
    V3 = g(V2, M, S, 3, 7, 11, 15, 5, 6),
    V4 = g(V3, M, S, 4, 8, 12, 16, 7, 8),
    V5 = g(V4, M, S, 1, 6, 11, 16, 9, 10),
    V6 = g(V5, M, S, 2, 7, 12, 13, 11, 12),
    V7 = g(V6, M, S, 3, 8, 9, 14, 13, 14),
    g(V7, M, S, 4, 5, 10, 15, 15, 16).

%% G mixing: 1-based tuple indices A B C D; X Y are sigma positions (1-based)
%% into the message block.
g(V, M, S, A, B, C, D, XPos, YPos) ->
    X = element(element(XPos, S) + 1, M),
    Y = element(element(YPos, S) + 1, M),
    A1 = (element(A, V) + element(B, V) + X) band ?M64,
    D1 = ror(element(D, V) bxor A1, 32),
    C1 = (element(C, V) + D1) band ?M64,
    B1 = ror(element(B, V) bxor C1, 24),
    A2 = (A1 + B1 + Y) band ?M64,
    D2 = ror(D1 bxor A2, 16),
    C2 = (C1 + D2) band ?M64,
    B2 = ror(B1 bxor C2, 63),
    setelement(A, setelement(B, setelement(C, setelement(D, V, D2), C2), B2), A2).

ror(X, R) ->
    ((X bsr R) bor (X bsl (64 - R))) band ?M64.

