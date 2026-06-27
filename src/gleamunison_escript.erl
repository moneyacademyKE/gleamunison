-module(gleamunison_escript).
-export([main/1]).
main(Args) -> gleamunison:run([list_to_binary(A) || A <- Args]).
