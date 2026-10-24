-module(gleamunison_source_budget).
-export([check/6]).

%% A single raw-byte pass precedes grapheme allocation. ASCII syntax bytes
%% cannot occur inside UTF-8 continuation bytes. Syntax errors stay with the
%% parser; this pass counts resource consumption, including nested quotes.
check(Source, MaxBytes, MaxTokens, MaxDepth, MaxForms, MaxTokenBytes)
  when is_binary(Source), is_integer(MaxBytes), MaxBytes > 0,
       is_integer(MaxTokens), MaxTokens > 0, is_integer(MaxDepth), MaxDepth > 0,
       is_integer(MaxForms), MaxForms > 0, is_integer(MaxTokenBytes), MaxTokenBytes > 0 ->
    case byte_size(Source) > MaxBytes of
        true -> {error, <<"source limit: bytes">>};
        false -> scan(Source, normal, 0, [], 0, 0, 0, 0,
                      {MaxTokens, MaxDepth, MaxForms, MaxTokenBytes})
    end;
check(_, _, _, _, _, _) -> {error, <<"source limit: invalid budget">>}.

%% Stack holds each list's depth charge (its parent quotes plus one).
%% D includes all active lists/quotes; Q is the quotes of the current term.
%% Scalar counters keep the preflight O(bytes), not O(bytes * nesting).
scan(_, _, N, _, D, _, F, Size, {MT, MD, MF, MS})
  when N > MT; D > MD; F > MF; Size > MS ->
    Reason = if N > MT -> <<"tokens">>;
                D > MD -> <<"depth">>;
                F > MF -> <<"forms">>;
                true -> <<"token bytes">> end,
    {error, <<"source limit: ", Reason/binary>>};
scan(<<>>, _, _, _, _, _, _, _, _) -> {ok, nil};
scan(<<$\n, Rest/binary>>, comment, N, S, D, Q, F, _, L) ->
    scan(Rest, normal, N, S, D, Q, F, 0, L);
scan(<<_, Rest/binary>>, comment, N, S, D, Q, F, Size, L) ->
    scan(Rest, comment, N, S, D, Q, F, Size + 1, L);
scan(<<$\\, C, Rest/binary>>, text, N, S, D, Q, F, Size, L)
  when C =:= $"; C =:= $\\; C =:= $n ->
    scan(Rest, text, N, S, D, Q, F, Size + 2, L);
scan(<<$", Rest/binary>>, text, N, S, D, Q, F, Size, L) ->
    scan(Rest, normal, N, S, D - Q, 0, F, Size + 1, L);
scan(<<_, Rest/binary>>, text, N, S, D, Q, F, Size, L) ->
    scan(Rest, text, N, S, D, Q, F, Size + 1, L);
scan(<<C, _/binary>> = Bin, atom, N, S, D, Q, F, _, L)
  when C =:= $\n; C =:= $\t; C =:= $\s; C =:= $(; C =:= $);
       C =:= $;; C =:= $' ->
    scan(Bin, normal, N, S, D - Q, 0, F, 0, L);
scan(<<_, Rest/binary>>, atom, N, S, D, Q, F, Size, L) ->
    scan(Rest, atom, N, S, D, Q, F, Size + 1, L);
scan(<<C, Rest/binary>>, normal, N, S, D, Q, F, _, L)
  when C =:= $\n; C =:= $\t; C =:= $\s ->
    scan(Rest, normal, N, S, D, Q, F, 0, L);
scan(<<$;, Rest/binary>>, normal, N, S, D, Q, F, _, L) ->
    scan(Rest, comment, N + 1, S, D, Q, F, 1, L);
scan(<<$', Rest/binary>>, normal, N, S, D, Q, F, _, L) ->
    scan(Rest, normal, N + 1, S, D + 1, Q + 1, form_start(S, Q, F), 0, L);
scan(<<$(, Rest/binary>>, normal, N, S, D, Q, F, _, L) ->
    scan(Rest, normal, N + 1, [Q + 1 | S], D + 1, 0, form_start(S, Q, F), 0, L);
scan(<<$), Rest/binary>>, normal, N, [], _, _, F, _, L) ->
    scan(Rest, normal, N + 1, [], 0, 0, F, 0, L);
scan(<<$), Rest/binary>>, normal, N, [Charge | S], D, Q, F, _, L) ->
    scan(Rest, normal, N + 1, S, D - Charge - Q, 0, F, 0, L);
scan(<<$", Rest/binary>>, normal, N, S, D, Q, F, _, L) ->
    scan(Rest, text, N + 1, S, D, Q, form_start(S, Q, F), 1, L);
scan(<<_, Rest/binary>>, normal, N, S, D, Q, F, _, L) ->
    scan(Rest, atom, N + 1, S, D, Q, form_start(S, Q, F), 1, L).

form_start([], 0, F) -> F + 1;
form_start(_, _, F) -> F.
