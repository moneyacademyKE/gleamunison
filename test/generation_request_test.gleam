import gleam/dict
import gleam/option.{Some}
import gleam/string
import gleamunison/generation_request
import gleamunison/schema_printer
import gleeunit/should

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn dynamic(value: a) -> b

pub fn request_rejects_storage_controls_and_unknown_signatures_test() {
  let branch_args =
    dict.from_list([
      #("template", dynamic("generate")),
      #("signature", dynamic("int")),
      #("branch", dynamic("other")),
    ])
  let assert Error(branch_error) = generation_request.plan(branch_args)
  string.contains(branch_error, "unknown argument") |> should.be_true

  let signature_args =
    dict.from_list([
      #("template", dynamic("generate")),
      #("signature", dynamic("anything the model likes")),
    ])
  let assert Error(signature_error) = generation_request.plan(signature_args)
  string.contains(signature_error, "signature must use") |> should.be_true
}

pub fn request_decodes_explicit_generation_target_test() {
  let args =
    dict.from_list([
      #("template", dynamic("generate a target and its helpers")),
      #("signature", dynamic("int")),
      #("target", dynamic("generated-number")),
    ])
  let assert Ok(plan) = generation_request.plan(args)
  plan.max_attempts |> should.equal(3)
  plan.target |> should.equal(Some("generated-number"))
  string.contains(plan.template, "target term named generated-number")
  |> should.be_true
}

pub fn request_rejects_empty_generation_target_test() {
  let args =
    dict.from_list([
      #("template", dynamic("generate")),
      #("signature", dynamic("int")),
      #("target", dynamic("  ")),
    ])
  let assert Error(message) = generation_request.plan(args)
  string.contains(message, "empty argument: target") |> should.be_true
}

pub fn request_decodes_function_signature_and_budget_test() {
  let args =
    dict.from_list([
      #("template", dynamic("make a greeter with {{signature}}")),
      #("signature", dynamic("(string, int) -> string")),
      #("max_attempts", dynamic(4)),
    ])
  let assert Ok(plan) = generation_request.plan(args)
  plan.max_attempts |> should.equal(4)
  plan.variables |> should.equal([])
  string.contains(plan.template, "exactly source and signature")
  |> should.be_true
}

pub fn request_decodes_durable_read_signature_test() {
  let args =
    dict.from_list([
      #("template", dynamic("read durable facts")),
      #("signature", dynamic("list")),
    ])
  let assert Ok(plan) = generation_request.plan(args)
  schema_printer.to_schema(plan.signature) |> should.equal("list")
}

pub fn request_rejects_non_string_variables_test() {
  let variables = dict.from_list([#("count", dynamic(3))])
  let args =
    dict.from_list([
      #("template", dynamic("generate")),
      #("signature", dynamic("int")),
      #("variables", dynamic(variables)),
    ])
  let assert Error(message) = generation_request.plan(args)
  string.contains(message, "variables must be a string map") |> should.be_true
}
