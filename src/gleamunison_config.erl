-module(gleamunison_config).
-export([get_env/1, get_all_env/0]).

get_env(Key) when is_binary(Key) ->
    case os:getenv(binary_to_list(Key)) of
        false -> {error, nil};
        Val -> {ok, list_to_binary(Val)}
    end.

get_all_env() ->
    [{list_to_binary(K), list_to_binary(V)} || {K, V} <- os:getenv()].
