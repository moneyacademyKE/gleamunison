-module(gleamunison_definition_codec).
-export([encode/1, decode/1, version/0]).

version() -> 1.

%% Wire bytes are recoverable data, not identity. Identity is recomputed by
%% codebase:hash_of_definition after decoding this bounded, versioned envelope.
encode(Definition) ->
    Encoded = term_to_binary(canonical(Definition), [{minor_version, 2}]),
    <<"GUDEF", 1, Encoded/binary>>.

%% Spans are not identity; requirement rows are sets. Canonical wire data
%% must agree so those differences cannot create a second payload per ref.
canonical({located, Inner, _Span}) -> canonical(Inner);
canonical({required, Requirements}) -> {required, lists:usort(canonical(Requirements))};
canonical(Value) when is_tuple(Value) ->
    list_to_tuple([canonical(V) || V <- tuple_to_list(Value)]);
canonical(Value) when is_list(Value) -> [canonical(V) || V <- Value];
canonical(Value) -> Value.

decode(<<"GUDEF", 1, 131, Tag, _/binary>> = Bytes)
        when Tag =/= 80, byte_size(Bytes) =< 1048576 ->
    <<"GUDEF", 1, Encoded/binary>> = Bytes,
    try
        {Definition, Used} = binary_to_term(Encoded, [safe, used]),
        true = Used =:= byte_size(Encoded),
        _Remaining = budget(Definition, 96, 20000),
        true = valid(definition, Definition),
        true = encode(Definition) =:= Bytes,
        {ok, Definition}
    catch
        _:_ -> {error, <<"invalid_definition_encoding">>}
    end;
decode(_) -> {error, <<"invalid_definition_encoding">>}.

%% No compressed ETF, functions, pids, refs, maps, atom creation, trailing
%% data, or recursive structures beyond the input budget cross this boundary.
budget(_, Depth, Remaining) when Depth =< 0; Remaining =< 0 -> error(input_limit);
budget(Value, Depth, Remaining) when is_tuple(Value) ->
    budget(tuple_to_list(Value), Depth - 1, Remaining - 1);
budget([Head | Tail], Depth, Remaining) ->
    budget(Tail, Depth, budget(Head, Depth - 1, Remaining - 1));
budget([], _Depth, Remaining) -> Remaining - 1;
budget(Value, _Depth, Remaining)
        when is_integer(Value); is_float(Value); is_binary(Value); is_atom(Value) ->
    Remaining - 1;
budget(_, _, _) -> error(invalid_value).

valid(definition, {term_def, Term, Type}) -> valid(term, Term) andalso valid(type, Type);
valid(definition, {type_def, Declaration}) -> valid(declaration, Declaration);
valid(definition, {ability_decl, {ability_declaration, Name, Ops}}) ->
    valid(local, Name) andalso all(operation, Ops);
valid(term, {ref_to, Ref}) -> valid(ref, Ref);
valid(term, {local_var_ref, Local}) -> valid(local, Local);
valid(term, {int, N}) -> is_integer(N);
valid(term, {float, N}) -> is_float(N);
valid(term, {text, Bytes}) -> is_binary(Bytes);
valid(term, {list, Terms}) -> all(term, Terms);
valid(term, {apply, Function, Arg}) -> valid(term, Function) andalso valid(term, Arg);
valid(term, {lambda, Binder, Body}) -> valid(local, Binder) andalso valid(term, Body);
valid(term, {'let', Binder, Value, Body}) ->
    valid(local, Binder) andalso valid(term, Value) andalso valid(term, Body);
valid(term, {match, Scrutinee, Cases}) -> valid(term, Scrutinee) andalso all('case', Cases);
valid(term, {do, Ability, Op, Args}) ->
    valid(ref, Ability) andalso valid(local, Op) andalso all(term, Args);
valid(term, {handle, Computation, Handler, Ability}) ->
    valid(term, Computation) andalso valid(term, Handler) andalso valid(ref, Ability);
valid(term, {construct, Ref, Args}) -> valid(ref, Ref) andalso all(term, Args);
valid(term, hole) -> true;
valid(term, {use, Binder, Call, Body}) ->
    valid(local, Binder) andalso valid(term, Call) andalso valid(term, Body);
valid(term, {located, Inner, {span, Line, Column}}) ->
    valid(term, Inner) andalso nonnegative(Line) andalso nonnegative(Column);
valid('case', {'case', Pattern, Guard, Body}) ->
    valid(pattern, Pattern) andalso valid(guard, Guard) andalso valid(term, Body);
valid(guard, none) -> true;
valid(guard, {some, {guard_term, Term}}) -> valid(term, Term);
valid(pattern, {pat_var, Local}) -> valid(local, Local);
valid(pattern, {pat_int, N}) -> is_integer(N);
valid(pattern, {pat_text, Bytes}) -> is_binary(Bytes);
valid(pattern, {pat_cons, Head, Tail}) -> valid(local, Head) andalso valid(local, Tail);
valid(pattern, pat_empty_list) -> true;
valid(pattern, {pat_as, Binder, Inner}) -> valid(local, Binder) andalso valid(pattern, Inner);
valid(pattern, {pat_constructor, Ref, Args}) -> valid(ref, Ref) andalso all(pattern, Args);
valid(type, {type_var, N}) -> nonnegative(N);
valid(type, {ability_var, N}) -> nonnegative(N);
valid(type, {fn, Params, Result, {required, Requirements}}) ->
    all(type, Params) andalso valid(type, Result) andalso all(requirement, Requirements);
valid(type, {app, Ref, Args}) -> valid(ref, Ref) andalso all(type, Args);
valid(type, {builtin, Builtin}) -> valid(builtin, Builtin);
valid(requirement, {concrete, {ability_ref, Ref}}) -> valid(ref, Ref);
valid(requirement, {req_var, N}) -> nonnegative(N);
valid(declaration, {structural, Name, Params, Constructors}) ->
    valid(local, Name) andalso all(local, Params) andalso all(constructor, Constructors);
valid(declaration, {unique, Name, Guid, Params, Constructors}) ->
    valid(local, Name) andalso is_binary(Guid) andalso
    unicode:characters_to_binary(Guid, utf8, utf8) =:= Guid andalso
    all(local, Params) andalso all(constructor, Constructors);
valid(constructor, {constructor, Name, Args}) -> valid(local, Name) andalso all(type_ref, Args);
valid(type_ref, {type_ref_var, Local}) -> valid(local, Local);
valid(type_ref, {type_con, Ref}) -> valid(ref, Ref);
valid(type_ref, {type_ref_builtin, Builtin}) -> valid(builtin, Builtin);
valid(operation, {operation, Name, Inputs, Output}) ->
    valid(local, Name) andalso all(type_ref, Inputs) andalso valid(type_ref, Output);
valid(ref, {ref, {hash, Hash}}) -> is_binary(Hash) andalso byte_size(Hash) =:= 32;
valid(local, {local, N}) -> nonnegative(N);
valid(builtin, Value) ->
    lists:member(Value, [int_type, float_type, text_type, bool_type, list_type, handler_type]);
valid(_, _) -> false.

all(Type, Values) when is_list(Values) -> lists:all(fun(V) -> valid(Type, V) end, Values);
all(_, _) -> false.

nonnegative(N) -> is_integer(N) andalso N >= 0.
