import gleam/bit_array
import gleam/list

pub type TemplateError {
  TemplateError(reason: String)
}

@external(erlang, "gleamunison_template", "interpolate")
fn ffi_interpolate(
  template: BitArray,
  vars: List(#(BitArray, BitArray)),
) -> Result(BitArray, BitArray)

fn unpack(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    _ -> ""
  }
}

pub fn render(
  template: String,
  vars: List(#(String, String)),
) -> Result(String, TemplateError) {
  let bin_vars =
    list.map(vars, fn(kv) {
      let #(k, v) = kv
      #(bit_array.from_string(k), bit_array.from_string(v))
    })
  case ffi_interpolate(bit_array.from_string(template), bin_vars) {
    Ok(result) -> Ok(unpack(result))
    Error(e) -> Error(TemplateError(unpack(e)))
  }
}
