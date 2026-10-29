pub opaque type DateTime {
  DateTime(timestamp: Int)
}

pub type DateTimeError {
  ParseError(reason: String)
}

@external(erlang, "gleamunison_datetime", "now")
fn ffi_now() -> Int

pub fn now() -> DateTime {
  DateTime(ffi_now())
}

/// Seconds since the Unix epoch.
pub fn to_unix(dt: DateTime) -> Int {
  let DateTime(ts) = dt
  ts
}
