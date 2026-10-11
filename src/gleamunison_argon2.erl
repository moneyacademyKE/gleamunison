%% Argon2id (RFC 9106, version 0x13) in pure Erlang over gleamunison_blake2b.
%% Indexing follows the reference implementation's fill_segment exactly;
%% verified against the RFC 9106 section 5.3 test vector (including the
%% per-pass intermediate block values).
-module(gleamunison_argon2).
-export([hash/8, h0/8]).

-define(M64, 16#FFFFFFFFFFFFFFFF).
-define(M32, 16#FFFFFFFF).
-define(VERSION, 16#13).
-define(TYPE_ID, 2).
-define(ZERO_BLOCK_WORDS, list_to_tuple(lists:duplicate(128, 0))).

hash(P, S, K, X, Passes, MemKiB, Par, TagLen)
  when is_binary(P), is_binary(S), is_binary(K), is_binary(X),
       is_integer(Passes), is_integer(MemKiB), is_integer(Par),
       is_integer(TagLen), Passes >= 1, Par >= 1, TagLen >= 4,
       MemKiB >= 8 * Par ->
    MPrime = 4 * Par * (MemKiB div (4 * Par)),
    LaneLen = MPrime div Par,
    SegLen = LaneLen div 4,
    H0 = h0(P, S, K, X, Passes, MemKiB, Par, TagLen),
    Mem0 = init_memory(H0, Par),
    Mem = fill(Mem0, Passes, Par, LaneLen, SegLen, MPrime),
    C = lists:foldl(
        fun(L, Acc) -> xor_blocks(Acc, maps:get({L, LaneLen - 1}, Mem)) end,
        maps:get({0, LaneLen - 1}, Mem),
        lists:seq(1, Par - 1)),
    h_prime(TagLen, C);
hash(_, _, _, _, _, _, _, _) ->
    {error, <<"invalid argon2 parameters">>}.

h0(P, S, K, X, Passes, MemKiB, Par, TagLen) ->
    gleamunison_blake2b:hash(
        <<Par:32/little, TagLen:32/little, MemKiB:32/little,
          Passes:32/little, ?VERSION:32/little, ?TYPE_ID:32/little,
          (byte_size(P)):32/little, P/binary,
          (byte_size(S)):32/little, S/binary,
          (byte_size(K)):32/little, K/binary,
          (byte_size(X)):32/little, X/binary>>,
        64).

%% B[i][0] and B[i][1] for every lane.
init_memory(H0, Par) ->
    lists:foldl(
        fun(L, Acc) ->
            B0 = h_prime(1024, <<H0/binary, 0:32/little, L:32/little>>),
            B1 = h_prime(1024, <<H0/binary, 1:32/little, L:32/little>>),
            Acc#{{L, 0} => B0, {L, 1} => B1}
        end,
        #{},
        lists:seq(0, Par - 1)).

fill(Mem, Passes, Par, LaneLen, SegLen, MPrime) ->
    lists:foldl(
        fun(Pass, M1) ->
            lists:foldl(
                fun(Slice, M2) ->
                    lists:foldl(
                        fun(Lane, M3) ->
                            fill_segment(M3, Pass, Lane, Slice,
                                         LaneLen, SegLen, MPrime, Passes, Par)
                        end,
                        M2,
                        lists:seq(0, Par - 1))
                end,
                M1,
                lists:seq(0, 3))
        end,
        Mem,
        lists:seq(0, Passes - 1)).

fill_segment(Mem, Pass, Lane, Slice, LaneLen, SegLen, MPrime, Passes, Par) ->
    DataIndependent = (Pass =:= 0) andalso (Slice =:= 0 orelse Slice =:= 1),
    StartIndex = case Pass =:= 0 andalso Slice =:= 0 of
        true -> 2;
        false -> 0
    end,
    Addr0 = case DataIndependent of
        true ->
            Z = <<Pass:64/little, Lane:64/little, Slice:64/little,
                  MPrime:64/little, Passes:64/little, ?TYPE_ID:64/little>>,
            %% Reference rule: for pass 0 slice 0 the first address block
            %% is generated before the loop (starting_index = 2 skips the
            %% i == 0 trigger).
            Input = <<Z/binary, 1:64/little, 0:968/unit:8>>,
            case StartIndex of
                2 -> {Input, 1, compress_g(zero_block(), compress_g(zero_block(), Input))};
                _ -> {Input, 0, zero_block()}
            end;
        false ->
            none
    end,
    Curr0 = Lane * LaneLen + Slice * SegLen + StartIndex,
    Prev0 = case Curr0 rem LaneLen of
        0 -> Curr0 + LaneLen - 1;
        _ -> Curr0 - 1
    end,
    fill_blocks(Mem, Pass, Lane, Slice, LaneLen, SegLen, Par,
                StartIndex, SegLen, Curr0, Prev0, DataIndependent, Addr0).

fill_blocks(Mem, _Pass, _Lane, _Slice, _LaneLen, _SegLen, _Par,
            I, SegLen, _Curr, _Prev, _DI, _Addr) when I >= SegLen ->
    Mem;
fill_blocks(Mem, Pass, Lane, Slice, LaneLen, SegLen, Par,
            I, SegLen, Curr, Prev, DataIndependent, Addr) ->
    {Pseudo, Addr1} = case DataIndependent of
        true ->
            {Input, Counter, CurrBlock} = Addr,
            case I rem 128 of
                0 ->
                    C1 = Counter + 1,
                    <<Z:48/binary, _:64/little, _/binary>> = Input,
                    In1 = <<Z/binary, C1:64/little, 0:968/unit:8>>,
                    B1 = compress_g(zero_block(), compress_g(zero_block(), In1)),
                    {nth_word(I rem 128, B1), {In1, C1, B1}};
                _ ->
                    {nth_word(I rem 128, CurrBlock), Addr}
            end;
        false ->
            <<W:64/little, _/binary>> = maps:get({Lane, Prev rem LaneLen}, Mem),
            {W, Addr}
    end,
    J1 = Pseudo band ?M32,
    J2 = (Pseudo bsr 32) band ?M32,
    RefLane0 = J2 rem Par,
    RefLane = case Pass =:= 0 andalso Slice =:= 0 of
        true -> Lane;
        false -> RefLane0
    end,
    SameLane = RefLane =:= Lane,
    AreaSize = reference_area_size(Pass, Slice, SegLen, LaneLen, I, SameLane),
    RelPos = relative_position(J1, AreaSize),
    StartPos = case Pass of
        0 -> 0;
        _ -> ((Slice + 1) * SegLen) rem LaneLen
    end,
    AbsPos = (StartPos + RelPos) rem LaneLen,
    RefBlock = maps:get({RefLane, AbsPos}, Mem),
    PrevBlock = maps:get({Lane, Prev rem LaneLen}, Mem),
    New0 = compress_g(PrevBlock, RefBlock),
    New = case Pass of
        0 -> New0;
        _ -> xor_blocks(New0, maps:get({Lane, Curr rem LaneLen}, Mem))
    end,
    Mem1 = Mem#{{Lane, Curr rem LaneLen} => New},
    fill_blocks(Mem1, Pass, Lane, Slice, LaneLen, SegLen, Par,
                I + 1, SegLen, Curr + 1, Curr, DataIndependent, Addr1).

reference_area_size(Pass, Slice, SegLen, LaneLen, I, SameLane) ->
    case {Pass, SameLane} of
        {0, true} ->
            case Slice of
                0 -> I - 1;
                _ -> Slice * SegLen + I - 1
            end;
        {0, false} ->
            Slice * SegLen + case I of
                0 -> -1;
                _ -> 0
            end;
        {_, true} ->
            LaneLen - SegLen + I - 1;
        {_, false} ->
            LaneLen - SegLen + case I of
                0 -> -1;
                _ -> 0
            end
    end.

relative_position(_J1, AreaSize) when AreaSize =< 1 ->
    0;
relative_position(J1, AreaSize) ->
    X = (J1 * J1) bsr 32,
    Y = (AreaSize * X) bsr 32,
    AreaSize - 1 - Y.

%% RFC 9106 section 3.3: H'
h_prime(T, A) when T =< 64 ->
    gleamunison_blake2b:hash(<<T:32/little, A/binary>>, T);
h_prime(T, A) ->
    R = (T + 31) div 32 - 2,
    V1 = gleamunison_blake2b:hash(<<T:32/little, A/binary>>, 64),
    {Heads, Vr} = h_prime_loop(R, V1, []),
    Last = gleamunison_blake2b:hash(Vr, T - 32 * R),
    iolist_to_binary([Heads, Last]).

h_prime_loop(1, V, Acc) ->
    %% Take W_R from V_R but keep V_R itself for the final hash.
    <<W:32/binary, _/binary>> = V,
    {lists:reverse([W | Acc]), V};
h_prime_loop(N, V, Acc) when N > 1 ->
    <<W:32/binary, _/binary>> = V,
    h_prime_loop(N - 1, gleamunison_blake2b:hash(V, 64), [W | Acc]).

%% RFC 9106 section 3.5: G(X, Y) = P(P(R rows) columns) XOR R, R = X XOR Y
compress_g(X, Y) when is_binary(X), is_binary(Y) ->
    R = xor_blocks(X, Y),
    Words = list_to_tuple([W || <<W:64/little>> <= R]),
    AfterRows = lists:foldl(
        fun(Row, Acc) -> apply_p(Acc, row_indices(Row)) end,
        Words, lists:seq(0, 7)),
    AfterCols = lists:foldl(
        fun(Col, Acc) -> apply_p(Acc, col_indices(Col)) end,
        AfterRows, lists:seq(0, 7)),
    Z = iolist_to_binary([<<W:64/little>> || W <- tuple_to_list(AfterCols)]),
    xor_blocks(Z, R).

row_indices(Row) ->
    lists:seq(16 * Row + 1, 16 * Row + 16).

col_indices(Col) ->
    %% Interleaved register pairs: words (16r+2c, 16r+2c+1) per row r.
    lists:flatten([[16 * R + 2 * Col + 1, 16 * R + 2 * Col + 2]
                   || R <- lists:seq(0, 7)]).

apply_p(Words, Idx) ->
    [V1, V2, V3, V4, V5, V6, V7, V8, V9, V10, V11, V12, V13, V14, V15, V16] =
        [element(Ix, Words) || Ix <- Idx],
    S0 = {V1, V2, V3, V4, V5, V6, V7, V8, V9, V10, V11, V12, V13, V14, V15, V16},
    S1 = gb(S0, 1, 5, 9, 13),
    S2 = gb(S1, 2, 6, 10, 14),
    S3 = gb(S2, 3, 7, 11, 15),
    S4 = gb(S3, 4, 8, 12, 16),
    S5 = gb(S4, 1, 6, 11, 16),
    S6 = gb(S5, 2, 7, 12, 13),
    S7 = gb(S6, 3, 8, 9, 14),
    S8 = gb(S7, 4, 5, 10, 15),
    lists:foldl(
        fun({Ix, Pos}, Acc) -> setelement(Ix, Acc, element(Pos, S8)) end,
        Words,
        lists:zip(Idx, lists:seq(1, 16))).

%% RFC 9106 section 3.6: GB with multiplication (Argon2's P inner function).
gb(V, A, B, C, D) ->
    A1 = fmix(element(A, V), element(B, V)),
    D1 = ror(element(D, V) bxor A1, 32),
    C1 = fmix(element(C, V), D1),
    B1 = ror(element(B, V) bxor C1, 24),
    A2 = fmix(A1, B1),
    D2 = ror(D1 bxor A2, 16),
    C2 = fmix(C1, D2),
    B2 = ror(B1 bxor C2, 63),
    setelement(A, setelement(B, setelement(C, setelement(D, V, D2), C2), B2), A2).

fmix(A, B) ->
    (A + B + 2 * (A band ?M32) * (B band ?M32)) band ?M64.

ror(X, R) ->
    ((X bsr R) bor (X bsl (64 - R))) band ?M64.

nth_word(N, Block) ->
    Offset = N * 8,
    <<_:Offset/binary, W:64/little, _/binary>> = Block,
    W.

xor_blocks(A, B) ->
    xor_blocks(A, B, <<>>).

xor_blocks(<<>>, <<>>, Acc) ->
    Acc;
xor_blocks(<<A:8, ARest/binary>>, <<B:8, BRest/binary>>, Acc) ->
    xor_blocks(ARest, BRest, <<Acc/binary, (A bxor B):8>>).

zero_block() ->
    <<0:1024/unit:8>>.
