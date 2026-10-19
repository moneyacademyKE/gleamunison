-module(input_boundary_ffi).
-export([never_raises/0]).

never_raises() ->
    lists:all(fun({Fun, Value}) ->
        try Fun(Value) of
            {error, Reason} when is_binary(Reason) -> true;
            _ -> false
        catch _:_ -> false
        end
    end, [{fun gleamunison_ffi:hex_to_bytes/1, <<"nope">>},
          {fun gleamunison_ffi:hex_to_bytes/1, <<"a">>},
          {fun gleamunison_ffi_io:hex_to_ref/1, <<"abcd">>},
          {fun gleamunison_ffi_io:sync_connect/1, <<"bad:abc">>}]).
