import gleam/list
import gleam/string
import gleamunison/identity
import gleeunit/should

// Pin the runtime contract so these regressions can run against the old,
// unchecked implementation before the public signature is corrected.
@external(erlang, "gleamunison@manifest", "ref_from_hex")
fn parse_ref(hex: String) -> Result(identity.DefinitionRef, String)

@external(erlang, "gleamunison_ffi_io", "parse_host_port")
fn parse_peer(peer: String) -> Result(#(String, Int), String)

@external(erlang, "input_boundary_ffi", "never_raises")
fn ffi_never_raises() -> Bool

pub fn malformed_ref_returns_error_test() {
  list.each(
    ["nope", "f", "", string.repeat("a", 62), string.repeat("g", 64)],
    fn(hex) { parse_ref(hex) |> should.be_error },
  )
}

pub fn sha256_hex_is_case_insensitive_test() {
  let assert Ok(lower) = parse_ref(string.repeat("ab", 32))
  let assert Ok(upper) = parse_ref(string.repeat("AB", 32))
  lower |> should.equal(upper)
}

pub fn malformed_peer_returns_error_test() {
  list.each(
    [
      "bad:abc",
      "",
      ":80",
      "host:",
      "host:0",
      "host:65536",
      "host:-1",
      "host: 80",
      "host:1:80",
    ],
    fn(peer) { parse_peer(peer) |> should.be_error },
  )
}

pub fn valid_peer_preserves_host_and_port_test() {
  parse_peer("localhost:65535") |> should.equal(Ok(#("localhost", 65_535)))
  parse_peer("127.0.0.1:1") |> should.equal(Ok(#("127.0.0.1", 1)))
}

pub fn erlang_input_boundary_never_raises_test() {
  ffi_never_raises() |> should.be_true
}
