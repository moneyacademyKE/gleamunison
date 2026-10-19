-module(gleamunison_peer).
-export([parse/1]).

%% Peer syntax is data, not a DNS lookup or a socket side effect.
parse(Name) when is_binary(Name), byte_size(Name) > 0, byte_size(Name) =< 320 ->
    case Name of
        <<"[", Rest/binary>> ->
            case binary:split(Rest, <<"]">>) of
                [Host, <<":", Port/binary>>] -> ipv6(Host, Port);
                _ -> invalid()
            end;
        _ ->
            case binary:split(Name, <<":">>, [global]) of
                [Host] -> host_port(Host, integer_to_binary(gleamunison_tcp_sync:get_port()));
                [Host, Port] -> host_port(Host, Port);
                _ -> invalid()
            end
    end;
parse(_) -> invalid().

host_port(Host, Port) ->
    case byte_size(Host) > 0 andalso byte_size(Host) =< 253 andalso valid_host(Host) of
        true -> port(Host, Port);
        false -> invalid()
    end.

valid_host(<<>>) -> true;
valid_host(<<C, Rest/binary>>) when C >= $a, C =< $z; C >= $A, C =< $Z;
                                  C >= $0, C =< $9; C =:= $.; C =:= $-; C =:= $_ ->
    valid_host(Rest);
valid_host(_) -> false.

ipv6(Host, Port) ->
    case inet:parse_ipv6_address(binary_to_list(Host)) of
        {ok, _} -> port(Host, Port);
        _ -> invalid()
    end.

port(Host, Port) when byte_size(Port) > 0, byte_size(Port) =< 5 ->
    case digits(Port) of
        true ->
            case binary_to_integer(Port) of
                N when N >= 1, N =< 65535 -> {ok, {Host, N}};
                _ -> invalid()
            end;
        false -> invalid()
    end;
port(_, _) -> invalid().

digits(<<>>) -> true;
digits(<<C, Rest/binary>>) when C >= $0, C =< $9 -> digits(Rest);
digits(_) -> false.

invalid() -> {error, <<"invalid peer: expected host[:port] (port 1..65535), or [IPv6]:port">>}.
