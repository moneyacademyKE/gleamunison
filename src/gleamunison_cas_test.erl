-module(gleamunison_cas_test).
-export([encode_definition/1, scratch_path/0, receive_defs/1, invalid_payloads/0,
         tcp_push/1, tcp_invalid_message/1]).

encode_definition(Definition) ->
    Encoded = term_to_binary(Definition, [{minor_version, 2}]),
    <<"GUDEF", 1, Encoded/binary>>.

scratch_path() ->
    Time = integer_to_binary(erlang:system_time(nanosecond)),
    Id = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    <<"build/cas_admission_", Time/binary, "_", Id/binary, ".dets">>.

receive_defs(Defs) ->
    case gleamunison_ffi_io:receive_pushed_defs(Defs) of
        ok -> {ok, nil};
        {error, Reason} -> {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
    end.

invalid_payloads() ->
    Type = {builtin, int_type},
    Ref = {ref, {hash, <<0:256>>}},
    Bad = [
        {term_def, {local_var_ref, {local, -1}}, Type},
        {term_def, {ref_to, {ref, {hash, <<0:248>>}}}, Type},
        {term_def, {int, 1}, {fn, [], Type, {required, [invalid_requirement]}}},
        {type_def, {unique, {local, 0}, <<255>>, [], []}},
        {ability_decl, {ability_declaration, {local, -1}, []}},
        {term_def, {int, 1}, {app, Ref, [invalid_type]}},
        {term_def, {list, [{int, 1} | improper_tail]}, Type},
        {term_def, {int, 1}, #{bad => type}},
        fun() -> error(must_never_execute) end,
        self(), make_ref()
    ],
    Compressed = term_to_binary({term_def, {text, binary:copy(<<0>>, 10000)}, Type}, [compressed]),
    [<<"GUDEF", 1, Compressed/binary>> | [encode_definition(Value) || Value <- Bad]].

tcp_push(Defs) ->
    with_tcp(fun(Port) ->
        case gleamunison_tcp_sync:send_message({<<"127.0.0.1">>, Port},
                {<<"cas-e2e">>, {push_defs, Defs}}) of
            {ok, ok} -> {ok, nil};
            {ok, {error, Reason}} -> {error, Reason};
            {error, Reason} -> {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
        end
    end).

tcp_invalid_message(Mode) ->
    with_tcp(fun(Port) ->
        Request = {<<"cas-e2e">>, {connect, <<"cas-e2e">>}},
        Encoded = term_to_binary(Request),
        Bytes = case Mode of
            0 -> term_to_binary({Request, binary:copy(<<0>>, 10000)}, [compressed]);
            1 -> <<Encoded/binary, 0>>
        end,
        {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 2000),
        try
            ok = gen_tcp:send(Socket, <<(byte_size(Bytes)):32, Bytes/binary>>),
            {ok, <<Length:32>>} = gen_tcp:recv(Socket, 4, 2000),
            {ok, Reply} = gen_tcp:recv(Socket, Length, 2000),
            case binary_to_term(Reply, [safe]) of
                {error, <<"invalid message">>} -> true;
                _ -> false
            end
        after gen_tcp:close(Socket)
        end
    end).

with_tcp(Fun) ->
    Started = case whereis(gleamunison_tcp_sync) of
        undefined -> {ok, _} = gleamunison_tcp_sync:start_link(), true;
        _ -> false
    end,
    try Fun(gleamunison_tcp_sync:get_port())
    after
        case Started of true -> ok = gleamunison_tcp_sync:stop(); false -> ok end
    end.
