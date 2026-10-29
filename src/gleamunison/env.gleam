//// One environment read boundary.
////
//// Every process setting goes through envoy here instead of declaring its
//// own external. The helpers preserve the established meaning: absent and
//// empty both select a default, while boolean settings accept 1, true, or
//// yes case-insensitively.

import envoy
import gleam/string

/// Raw lookup. Absent is `Error(Nil)`; an empty value is still present.
pub fn get(key: String) -> Result(String, Nil) {
  envoy.get(key)
}

/// First non-empty value, else the default.
pub fn string_or(key: String, default: String) -> String {
  case envoy.get(key) {
    Ok(value) if value != "" -> value
    _ -> default
  }
}

/// Established boolean setting: `1`, `true`, or `yes`, case-insensitive.
pub fn flag(key: String) -> Bool {
  case envoy.get(key) {
    Ok(value) -> truthy(value)
    Error(_) -> False
  }
}

/// The same boolean rule applied to an already-read value.
pub fn truthy(value: String) -> Bool {
  case string.lowercase(value) {
    "1" | "true" | "yes" -> True
    _ -> False
  }
}
