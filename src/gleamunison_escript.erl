-module(gleamunison_escript).
-export([main/1]).
main(Args) ->
    ok = application:load(gleamunison),
    gleamunison:run([list_to_binary(A) || A <- Args]).
