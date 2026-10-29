//// Time for store logs, evidence, and trust windows.
////
//// The runtime stores whole Unix seconds and renders them as second-precision
//// Zulu timestamps. Birl owns calendar conversion; this module preserves the
//// project's stored and rendered shape.

import birl
import gleam/string

pub opaque type DateTime {
  DateTime(timestamp: Int)
}

pub fn now() -> DateTime {
  DateTime(now_unix())
}

/// Whole Unix seconds, the shape stored by logs and evidence.
pub fn now_unix() -> Int {
  birl.to_unix(birl.utc_now())
}

pub fn to_unix(dt: DateTime) -> Int {
  let DateTime(timestamp) = dt
  timestamp
}

/// Render whole Unix seconds exactly as the store log has always done:
/// `YYYY-MM-DDTHH:MM:SSZ`, with no fractional-second noise.
pub fn format_unix(seconds: Int) -> String {
  seconds
  |> birl.from_unix()
  |> birl.to_iso8601()
  |> second_precision_zulu()
}

fn second_precision_zulu(rendered: String) -> String {
  case string.ends_with(rendered, ".000Z") {
    True -> string.drop_end(rendered, 5) <> "Z"
    False -> rendered
  }
}
