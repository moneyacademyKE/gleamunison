//// The LLM test double, moved out of src (bk-baac): production composes
//// provider_handler directly inside llm.complete_env, so a mock handler is
//// test-only surface and must not ship in the package or the escript.

import gleam/dynamic.{type Dynamic}
import gleamunison/dynamic_ffi.{to_dynamic}
import gleamunison/effects.{type OpHandler}
import gleamunison/llm_types.{type Completion}
import gleamunison/llm_wire

/// Deterministic mock: always answers the same completion. The live call and
/// the test double are the same handler swap — that is the whole point.
pub fn mock_handler(response: Completion) -> OpHandler {
  fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    cont(to_dynamic(Ok(llm_wire.completion_json(response))))
  }
}
