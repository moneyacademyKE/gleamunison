//// Versioned definition payloads for storage and peer transfer.
//// Structural identity remains codebase.hash_of_definition, not these bytes.

import gleamunison/ast.{type Definition}

@external(erlang, "gleamunison_definition_codec", "encode")
pub fn encode(definition: Definition) -> BitArray

@external(erlang, "gleamunison_definition_codec", "decode")
pub fn decode(bytes: BitArray) -> Result(Definition, String)
