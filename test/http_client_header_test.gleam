import gleam/bit_array
import gleam/int
import gleam/string
import gleamunison/http_client

@external(erlang, "gleamunison_ffi_test", "start_echo_server")
fn start_echo_server() -> Result(Int, BitArray)

fn body_to_string(resp: http_client.HttpResponse) -> String {
  case bit_array.to_string(http_client.body(resp)) {
    Ok(s) -> s
    Error(_) -> ""
  }
}

pub fn post_with_headers_delivers_auth_and_json_content_type_test() {
  let assert Ok(port) = start_echo_server()
  let url = "http://127.0.0.1:" <> int.to_string(port) <> "/v1/chat/completions"
  let assert Ok(resp) =
    http_client.post_with_headers(
      url,
      [
        #("authorization", "Bearer test-key-123"),
        #("content-type", "application/json"),
      ],
      bit_array.from_string("{\"model\":\"test-model\"}"),
    )
  let assert True = http_client.status(resp) == 200
  // The echo body is what the SERVER saw — proves headers survive the FFI boundary.
  let seen = string.lowercase(body_to_string(resp))
  let assert True = string.contains(seen, "authorization: bearer test-key-123")
  let assert True = string.contains(seen, "content-type: application/json")
  let assert True = string.contains(seen, "body:{\"model\":\"test-model\"}")
}

pub fn post_without_headers_keeps_octet_stream_default_test() {
  let assert Ok(port) = start_echo_server()
  let url = "http://127.0.0.1:" <> int.to_string(port) <> "/legacy"
  let assert Ok(resp) =
    http_client.post(url, bit_array.from_string("raw-bytes"))
  let assert True = http_client.status(resp) == 200
  let seen = string.lowercase(body_to_string(resp))
  // Regression guard: the pre-change default must be preserved.
  let assert True =
    string.contains(seen, "content-type: application/octet-stream")
  let assert True = string.contains(seen, "body:raw-bytes")
}
