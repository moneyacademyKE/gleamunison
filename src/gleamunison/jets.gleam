import gleam/option.{type Option, None, Some}
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}

/// Returns the native Erlang delegation code if a DefinitionRef matches a registered jet.
pub fn get_jet(ref: DefinitionRef) -> Option(String) {
  let Ref(hash) = ref
  let debug_str = hash_to_debug_string(hash)

  case debug_str {
    // 123 padded to 256 bits (hex format) is our test fibonacci jet
    "000000000000000000000000000000000000000000000000000000000000007b" ->
      Some("fun(N) -> gleamunison_jets:fib(N) end")
    _ -> None
  }
}
