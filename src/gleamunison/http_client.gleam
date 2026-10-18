import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None}
import gleam/string
import gleamunison/cancellation

pub opaque type HttpResponse {
  HttpResponse(status: Int, headers: List(#(String, String)), body: BitArray)
}

pub fn status(resp: HttpResponse) -> Int {
  resp.status
}

pub fn body(resp: HttpResponse) -> BitArray {
  resp.body
}

pub fn headers(resp: HttpResponse) -> List(#(String, String)) {
  resp.headers
}

pub type HttpError {
  HttpError(reason: String)
}

@external(erlang, "gleamunison_http_client", "get")
fn ffi_get(
  url: BitArray,
) -> Result(#(Int, List(#(BitArray, BitArray)), BitArray), BitArray)

@external(erlang, "gleamunison_http_client", "post")
fn ffi_post(
  url: BitArray,
  body: BitArray,
) -> Result(#(Int, List(#(BitArray, BitArray)), BitArray), BitArray)

@external(erlang, "gleamunison_http_client", "put")
fn ffi_put(
  url: BitArray,
  body: BitArray,
) -> Result(#(Int, List(#(BitArray, BitArray)), BitArray), BitArray)

@external(erlang, "gleamunison_http_client", "delete")
fn ffi_delete(
  url: BitArray,
) -> Result(#(Int, List(#(BitArray, BitArray)), BitArray), BitArray)

fn pack(s: String) -> BitArray {
  bit_array.from_string(s)
}

fn unpack(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    _ -> ""
  }
}

fn map_headers(
  headers: List(#(BitArray, BitArray)),
) -> List(#(String, String)) {
  let res =
    list.map(headers, fn(kv) {
      let #(k, v) = kv
      #(unpack(k), unpack(v))
    })
  res
}

@external(erlang, "gleamunison_http_client", "request_with_options")
fn ffi_request_with_options(
  method: BitArray,
  url: BitArray,
  headers: List(#(BitArray, BitArray)),
  body: BitArray,
  timeout_ms: Int,
  cancellation: Option(cancellation.Token),
) -> Result(#(Int, List(#(BitArray, BitArray)), BitArray), BitArray)

/// Header-aware request — the general form; get/post/put/delete are the
/// no-header conveniences preserved for existing callers.
pub fn request(
  method: String,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
) -> Result(HttpResponse, HttpError) {
  request_with_options(method, url, headers, body, 180_000, None)
}

pub fn request_with_options(
  method: String,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
  timeout_ms: Int,
  cancellation: Option(cancellation.Token),
) -> Result(HttpResponse, HttpError) {
  let bin_headers =
    list.map(headers, fn(kv) {
      let #(k, v) = kv
      #(pack(k), pack(v))
    })
  let timeout = case timeout_ms {
    n if n < 1 -> 1
    n if n > 180_000 -> 180_000
    n -> n
  }
  case
    ffi_request_with_options(
      pack(string.uppercase(method)),
      pack(url),
      bin_headers,
      body,
      timeout,
      cancellation,
    )
  {
    Ok(#(status, resp_headers, resp_body)) ->
      Ok(HttpResponse(status, map_headers(resp_headers), resp_body))
    Error(e) -> Error(HttpError(unpack(e)))
  }
}

pub fn post_with_headers(
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
) -> Result(HttpResponse, HttpError) {
  request("POST", url, headers, body)
}

pub fn get(url: String) -> Result(HttpResponse, HttpError) {
  case ffi_get(pack(url)) {
    Ok(#(status, headers, body)) ->
      Ok(HttpResponse(status, map_headers(headers), body))
    Error(e) -> Error(HttpError(unpack(e)))
  }
}

pub fn post(url: String, body: BitArray) -> Result(HttpResponse, HttpError) {
  case ffi_post(pack(url), body) {
    Ok(#(status, headers, body)) ->
      Ok(HttpResponse(status, map_headers(headers), body))
    Error(e) -> Error(HttpError(unpack(e)))
  }
}

pub fn put(url: String, body: BitArray) -> Result(HttpResponse, HttpError) {
  case ffi_put(pack(url), body) {
    Ok(#(status, headers, body)) ->
      Ok(HttpResponse(status, map_headers(headers), body))
    Error(e) -> Error(HttpError(unpack(e)))
  }
}

pub fn delete(url: String) -> Result(HttpResponse, HttpError) {
  case ffi_delete(pack(url)) {
    Ok(#(status, headers, body)) ->
      Ok(HttpResponse(status, map_headers(headers), body))
    Error(e) -> Error(HttpError(unpack(e)))
  }
}
