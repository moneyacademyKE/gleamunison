import gleam/bit_array
import gleam/list

pub opaque type HttpResponse {
  HttpResponse(status: Int, headers: List(#(String, String)), body: BitArray)
}

pub type HttpError {
  HttpError(reason: String)
}

@external(erlang, "gleamunison_http_client", "get")
fn ffi_get(url: BitArray) -> Result(#(Int, List(#(BitArray, BitArray)), BitArray), BitArray)

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
  let res = list.map(headers, fn(kv) {
    let #(k, v) = kv
    #(unpack(k), unpack(v))
  })
  res
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
