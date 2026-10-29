import gleam/int
import gleam/io

@external(erlang, "gleamunison_http", "start_server")
fn ffi_start_server(port: Int) -> Nil

pub fn start_server(port: Int) -> Nil {
  io.println(
    "Starting Gleamunison web server on port " <> int.to_string(port) <> "...",
  )
  ffi_start_server(port)
}
