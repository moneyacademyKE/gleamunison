@external(erlang, "gleamunison_json", "encode")
pub fn encode(term: a) -> Result(BitArray, BitArray)

@external(erlang, "gleamunison_json", "decode")
pub fn decode(bin: BitArray) -> Result(a, BitArray)
