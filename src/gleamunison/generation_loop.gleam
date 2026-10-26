//// Bounded generation over the one admitted publication path.
//// Providers propose candidates; SAP, tests, evidence, and the branch decide.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/agent_publish
import gleamunison/agent_read_model
import gleamunison/ast
import gleamunison/codebase
import gleamunison/generation_candidate
import gleamunison/mcp
import gleamunison/patch
import gleamunison/prompt
import gleamunison/repl_eval
import gleamunison/schema_printer
import gleamunison/storage.{type StorageAdapter}

const max_attempts = 8

const max_prompt_bytes = 65_536

const max_candidate_bytes = 1_048_576

pub type Plan {
  Plan(
    template: String,
    variables: List(#(String, String)),
    signature: ast.Type,
    max_attempts: Int,
  )
}

pub type Attempt {
  Attempt(prompt: String, number: Int, previous_error: Option(String))
}

pub type Generator =
  fn(Attempt) -> String

pub type Provider =
  fn(Attempt) -> Result(String, String)

pub type Outcome {
  Outcome(
    attempts: Int,
    prompt_ref: String,
    rendered_prompt: String,
    publication: agent_publish.Publication,
    dependents: List(String),
  )
}

type Context {
  Context(
    adapter: StorageAdapter,
    log_directory: String,
    branch: String,
    max_attempts: Int,
    prompt_ref: String,
    rendered_prompt: String,
    signature: String,
    previous: List(agent_read_model.Entry),
    generator: Provider,
  )
}

pub fn generate_and_publish(
  adapter: StorageAdapter,
  log_directory: String,
  branch: String,
  untrusted: Bool,
  plan: Plan,
  generator: Generator,
) -> Result(Outcome, String) {
  generate_with_provider(
    adapter,
    log_directory,
    branch,
    untrusted,
    plan,
    fn(attempt) { Ok(generator(attempt)) },
  )
}

pub fn generate_with_provider(
  adapter: StorageAdapter,
  log_directory: String,
  branch: String,
  untrusted: Bool,
  plan: Plan,
  provider: Provider,
) -> Result(Outcome, String) {
  case untrusted {
    True -> Error("generation_refused: untrusted profile cannot write")
    False -> prepare(adapter, log_directory, branch, plan, provider)
  }
}

fn prepare(
  adapter: StorageAdapter,
  log_directory: String,
  branch: String,
  plan: Plan,
  provider: Provider,
) -> Result(Outcome, String) {
  use Nil <- result.try(validate_plan(plan))
  let signature = schema_printer.to_schema(plan.signature)
  use rendered <- result.try(
    prompt.render(plan.template, [#("signature", signature), ..plan.variables])
    |> result.map_error(fn(error) {
      "cannot render generation prompt: " <> string.inspect(error)
    }),
  )
  use Nil <- result.try(check_size(
    rendered,
    max_prompt_bytes,
    "generation prompt exceeds 65536 bytes",
  ))
  use #(previous, _) <- result.try(agent_read_model.load(adapter, branch))
  use #(_, prompt_ref) <- result.try(
    prompt.put_checked(codebase.with_adapter(adapter), plan.template)
    |> result.map_error(fn(error) {
      "cannot store generation prompt: " <> string.inspect(error)
    }),
  )
  attempt(
    Context(
      adapter:,
      log_directory:,
      branch:,
      max_attempts: plan.max_attempts,
      prompt_ref: prompt.ref_hex(prompt_ref),
      rendered_prompt: rendered,
      signature:,
      previous:,
      generator: provider,
    ),
    1,
    None,
  )
}

fn validate_plan(plan: Plan) -> Result(Nil, String) {
  case plan.max_attempts {
    n if n < 1 || n > max_attempts ->
      Error("generation attempts must be between 1 and 8")
    _ ->
      case string.trim(plan.template) {
        "" -> Error("generation prompt template is empty")
        _ ->
          case list.key_find(plan.variables, "signature") {
            Ok(_) -> Error("generation variable signature is reserved")
            Error(Nil) -> Ok(Nil)
          }
      }
  }
}

fn attempt(
  context: Context,
  number: Int,
  previous_error: Option(String),
) -> Result(Outcome, String) {
  case number > context.max_attempts {
    True -> Error(exhausted(context.max_attempts, previous_error))
    False -> {
      let request =
        Attempt(
          prompt_with_feedback(context.rendered_prompt, previous_error),
          number,
          previous_error,
        )
      case
        context.generator(request)
        |> result.try(fn(raw) { attempt_candidate(context, raw) })
      {
        Ok(publication) ->
          Ok(Outcome(
            attempts: number,
            prompt_ref: context.prompt_ref,
            rendered_prompt: context.rendered_prompt,
            publication:,
            dependents: direct_dependents(context.previous, publication),
          ))
        Error(reason) -> attempt(context, number + 1, Some(reason))
      }
    }
  }
}

fn prompt_with_feedback(
  base: String,
  previous_error: Option(String),
) -> String {
  case previous_error {
    None -> base
    Some(reason) ->
      base
      <> "\n\nThe previous candidate was rejected: "
      <> reason
      <> "\nReturn only a corrected JSON object with source and signature."
  }
}

fn attempt_candidate(
  context: Context,
  raw: String,
) -> Result(agent_publish.Publication, String) {
  use Nil <- result.try(check_size(
    raw,
    max_candidate_bytes,
    "generation candidate exceeds 1048576 bytes",
  ))
  use source <- result.try(generation_candidate.decode(raw, context.signature))
  agent_publish.publish_source_with_signature(
    context.adapter,
    source,
    context.branch,
    False,
    context.log_directory,
    context.signature,
  )
}

fn check_size(
  value: String,
  limit: Int,
  message: String,
) -> Result(Nil, String) {
  case bit_array.byte_size(bit_array.from_string(value)) <= limit {
    True -> Ok(Nil)
    False -> Error(message)
  }
}

fn exhausted(limit: Int, previous_error: Option(String)) -> String {
  let suffix = case limit {
    1 -> ""
    _ -> "s"
  }
  let reason = case previous_error {
    Some(message) -> message
    None -> "no candidate was attempted"
  }
  "generation exhausted "
  <> int.to_string(limit)
  <> " attempt"
  <> suffix
  <> ": "
  <> reason
}

pub fn json(outcome: Outcome) -> String {
  let dependents =
    outcome.dependents |> list.map(mcp.json_string) |> string.join(",")
  "{\"attempts\":"
  <> int.to_string(outcome.attempts)
  <> ",\"prompt_ref\":"
  <> mcp.json_string(outcome.prompt_ref)
  <> ",\"publication\":"
  <> agent_publish.json(outcome.publication)
  <> ",\"dependents\":["
  <> dependents
  <> "]}"
}

fn direct_dependents(
  entries: List(agent_read_model.Entry),
  publication: agent_publish.Publication,
) -> List(String) {
  let stored =
    list.filter_map(entries, fn(entry) {
      case entry {
        agent_read_model.Stored(name, ref, definition, _) ->
          Ok(#(name, ref, definition))
        _ -> Error(Nil)
      }
    })
  let definitions = list.map(stored, fn(item) { #(item.1, item.2) })
  publication.definitions
  |> list.flat_map(fn(published) {
    patch.dependents(definitions, repl_eval.ref_for_name(published.name))
  })
  |> list.unique
  |> list.filter_map(fn(ref) {
    case list.find(stored, fn(item) { item.1 == ref }) {
      Ok(item) -> Ok(item.0)
      Error(Nil) -> Error(Nil)
    }
  })
  |> list.sort(string.compare)
}
