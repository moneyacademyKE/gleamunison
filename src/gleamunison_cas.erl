-module(gleamunison_cas).
-export([verify/2, verify_batch/1]).

%% Adapters are trusted key/value primitives (also used for mutable branch
%% pointers). All untrusted content admission composes this verifier with one.
verify(Ref, Bytes) when is_binary(Ref), byte_size(Ref) =:= 32,
                        is_binary(Bytes), byte_size(Bytes) =< 1048576 ->
    case gleamunison_ffi:hash_bytes(Bytes) =:= Ref orelse
         gleamunison_ffi:hash_bytes(<<"promptdef:", Bytes/binary>>) =:= Ref of
        true -> {ok, nil};
        false -> verify_definition(Ref, Bytes)
    end;
verify(_, _) -> {error, <<"invalid_content_reference_or_size">>}.

verify_definition(Ref, Bytes) ->
    case gleamunison_definition_codec:decode(Bytes) of
        {ok, Definition} ->
            {hash, Computed} = gleamunison@codebase:hash_of_definition(Definition),
            case Computed =:= Ref of
                true -> {ok, nil};
                false -> {error, <<"content_hash_mismatch">>}
            end;
        {error, _} -> {error, <<"content_hash_mismatch_or_invalid_definition">>}
    end.

verify_batch(Defs) when is_list(Defs), length(Defs) =< 4096 ->
    verify_batch(Defs, #{});
verify_batch(_) -> {error, <<"invalid_definition_batch">>}.

verify_batch([], _Seen) -> {ok, []};
verify_batch([{Hex, Bytes} | Rest], Seen) when is_binary(Hex), byte_size(Hex) =:= 64 ->
    try
        {ok, Ref} = gleamunison_ffi:hex_to_bytes(Hex),
        true = is_binary(Ref) andalso byte_size(Ref) =:= 32,
        case verify(Ref, Bytes) of
            {error, _} = Error -> Error;
            {ok, nil} ->
                case maps:find(Ref, Seen) of
                    {ok, Other} when Other =/= Bytes -> {error, <<"content_conflict">>};
                    _ ->
                        case verify_batch(Rest, Seen#{Ref => Bytes}) of
                            {ok, Verified} -> {ok, [{Ref, Bytes} | Verified]};
                            {error, _} = Error -> Error
                        end
                end
        end
    catch _:_ -> {error, <<"invalid_content_reference">>}
    end;
verify_batch(_, _) -> {error, <<"invalid_definition_batch">>}.
