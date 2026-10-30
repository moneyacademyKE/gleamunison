import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleamunison/http_client

@external(erlang, "latin1_ffi", "start_header_server")
fn start_header_server() -> Result(Int, BitArray)

@external(erlang, "latin1_ffi", "start_error_server")
fn start_error_server() -> Result(Int, BitArray)

/// Regression (bk-8aae): a Latin-1 header value (byte 233, e-acute) used to
/// cross the FFI as invalid UTF-8, and unpack silently fell back to "".
pub fn latin1_header_value_arrives_as_decoded_utf8_test() {
  let assert Ok(port) = start_header_server()
  let url = "http://127.0.0.1:" <> int.to_string(port) <> "/latin1"
  let assert Ok(resp) = http_client.request("GET", url, [], <<>>)
  let assert True = http_client.status(resp) == 200
  let found =
    http_client.headers(resp)
    |> list.find_map(fn(pair) {
      let #(k, v) = pair
      case string.lowercase(k) {
        "x-latin1" -> Ok(v)
        _ -> Error(Nil)
      }
    })
  // "café" — the e-acute must arrive correctly decoded, not the old silent "".
  let assert Ok("café") = found
}

/// Regression (bk-8aae): httpc reports the malformed status line as
/// {invalid_version, "<233>OT"}; the ~p rendering used to cross the FFI as
/// invalid UTF-8, so the Gleam side saw "" instead of the reason.
pub fn latin1_error_reason_arrives_as_decoded_utf8_test() {
  let assert Ok(port) = start_error_server()
  let url = "http://127.0.0.1:" <> int.to_string(port) <> "/boom"
  let assert Error(http_client.HttpError(reason)) =
    http_client.request_with_options("GET", url, [], <<>>, 2000, None)
  let assert True = reason != ""
  let assert True = string.contains(reason, "invalid_version")
  let assert True = string.contains(reason, "é")
}
