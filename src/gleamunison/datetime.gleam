import gleam/bit_array

pub opaque type DateTime {
  DateTime(timestamp: Int)
}

pub type DateTimeError {
  ParseError(reason: String)
}

@external(erlang, "gleamunison_datetime", "now")
fn ffi_now() -> Int

@external(erlang, "gleamunison_datetime", "now_iso8601")
fn ffi_now_iso8601() -> BitArray

@external(erlang, "gleamunison_datetime", "format_iso8601")
fn ffi_format_iso8601(ts: Int) -> BitArray

@external(erlang, "gleamunison_datetime", "from_iso8601")
fn ffi_from_iso8601(iso: BitArray) -> Result(Int, BitArray)

@external(erlang, "gleamunison_datetime", "add_seconds")
fn ffi_add_seconds(ts: Int, n: Int) -> Int

@external(erlang, "gleamunison_datetime", "diff_seconds")
fn ffi_diff_seconds(t1: Int, t2: Int) -> Int

fn unpack(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    _ -> ""
  }
}

pub fn now() -> DateTime {
  DateTime(ffi_now())
}

pub fn now_iso8601() -> String {
  unpack(ffi_now_iso8601())
}

pub fn from_iso8601(iso: String) -> Result(DateTime, DateTimeError) {
  case ffi_from_iso8601(bit_array.from_string(iso)) {
    Ok(ts) -> Ok(DateTime(ts))
    Error(e) -> Error(ParseError(unpack(e)))
  }
}

pub fn to_iso8601(dt: DateTime) -> String {
  unpack(ffi_format_iso8601(dt.timestamp))
}

pub fn add_seconds(dt: DateTime, n: Int) -> DateTime {
  DateTime(ffi_add_seconds(dt.timestamp, n))
}

pub fn diff_seconds(a: DateTime, b: DateTime) -> Int {
  ffi_diff_seconds(a.timestamp, b.timestamp)
}
