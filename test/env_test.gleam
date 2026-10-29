import envoy
import gleam/list
import gleamunison/env
import gleeunit/should

const test_key = "GLEAMUNISON_ENV_HELPER_TEST"

pub fn get_preserves_empty_as_present_test() {
  envoy.set(test_key, "")
  env.get(test_key) |> should.equal(Ok(""))
  envoy.unset(test_key)
  env.get(test_key) |> should.equal(Error(Nil))
}

pub fn string_or_treats_absent_and_empty_as_default_test() {
  envoy.unset(test_key)
  env.string_or(test_key, "fallback") |> should.equal("fallback")

  envoy.set(test_key, "")
  env.string_or(test_key, "fallback") |> should.equal("fallback")

  envoy.set(test_key, "value")
  env.string_or(test_key, "fallback") |> should.equal("value")

  envoy.unset(test_key)
}

pub fn flag_accepts_the_established_truthy_values_test() {
  envoy.unset(test_key)
  env.flag(test_key) |> should.be_false

  list.each(["1", "true", "TRUE", "Yes"], fn(value) {
    envoy.set(test_key, value)
    env.flag(test_key) |> should.be_true
  })

  list.each(["", "0", "false", "no", "maybe"], fn(value) {
    envoy.set(test_key, value)
    env.flag(test_key) |> should.be_false
  })

  envoy.unset(test_key)
}
