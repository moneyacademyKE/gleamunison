-module(gleamunison_health).
-export([node_status/0]).

node_status() ->
    Node = atom_to_binary(node(), utf8),
    ModCount = length([M || {M, _} <- code:all_loaded(), lists:prefix("m_", atom_to_list(M))]),
    MemMB = erlang:memory(total) div 1024 div 1024,
    {Node, ModCount, MemMB}.
