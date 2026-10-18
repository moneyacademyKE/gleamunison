import gleam/string

@external(erlang, "gleamunison_ffi_test", "tcp_auth_probe")
fn ffi_tcp_auth_probe(mode: Int) -> String

pub fn sync_rejects_missing_token_test() {
  let result = ffi_tcp_auth_probe(0)
  let assert True = string.contains(result, "auth_required")
}

pub fn sync_accepts_valid_token_test() {
  let result = ffi_tcp_auth_probe(1)
  let assert True = string.contains(result, "ok")
}

pub fn sync_rejects_wrong_token_test() {
  let result = ffi_tcp_auth_probe(2)
  let assert True = string.contains(result, "auth_failed")
}

pub fn sync_rejects_oversized_frame_test() {
  let result = ffi_tcp_auth_probe(3)
  let assert True = string.contains(result, "message_too_large")
}
