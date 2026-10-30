import envoy
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleamunison/agent_publish
import gleamunison/app_route
import gleamunison/ast
import gleamunison/codebase
import gleamunison/dynamic_ffi.{to_dynamic}
import gleamunison/generation_loop
import gleamunison/identity
import gleamunison/json
import gleamunison/namespace
import gleamunison/prompt
import gleamunison/run_ref
import gleamunison/storage
import gleeunit/should
import simplifile
import test_ffi.{without_active_storage}

pub fn near_miss_generation_is_admitted_and_runnable_test() {
  with_store(fn(adapter, root) {
    let plan =
      generation_loop.Plan(
        template: "Task: {{task}}. Emit {{signature}} as JSON.",
        variables: [#("task", "a greeting")],
        signature: text_to_text(),
        max_attempts: 2,
        target: None,
      )
    let assert Ok(outcome) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        plan,
        fn(_) {
          "```json\n{source: '(define generated-greeting string-upcase)\\n(define test_generated-greeting (do Test expect 1))', signature: '(string) -> string',}\n```"
        },
      )
    outcome.attempts |> should.equal(1)
    string.length(outcome.prompt_ref) |> should.equal(64)
    string.contains(outcome.rendered_prompt, "Task: a greeting.")
    |> should.be_true
    string.contains(outcome.rendered_prompt, "(string) -> string")
    |> should.be_true
    prompt.get(codebase.with_adapter(adapter), ref(outcome.prompt_ref))
    |> should.equal(Ok(plan.template))
    let assert [published] = outcome.publication.definitions
    published.name |> should.equal("generated-greeting")
    run_ref.run_verified_on_branch(
      adapter,
      ref(published.content_ref),
      "factory",
      [to_dynamic("Moe")],
      False,
    )
    |> should.equal(Ok("<<\"MOE\">>"))
    let response =
      app_route.request(
        adapter,
        "factory",
        "generated-greeting",
        "{\"args\":[\"Moe\"]}",
      )
    response.status |> should.equal(200)
    string.contains(response.body, "MOE") |> should.be_true
  })
}

pub fn retry_receives_feedback_and_exhaustion_preserves_branch_test() {
  with_store(fn(adapter, root) {
    let plan =
      generation_loop.Plan(
        template: "generate code for {{signature}}",
        variables: [],
        signature: ast.Builtin(ast.IntType),
        max_attempts: 2,
        target: None,
      )
    let source =
      "(define generated-number 42)\n(define test_generated-number (do Test expect 1))"
    let assert Ok(outcome) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        plan,
        fn(attempt) {
          case attempt.number {
            1 -> "not JSON"
            _ -> {
              string.contains(
                attempt.prompt,
                "previous candidate was rejected: generation candidate contains no JSON",
              )
              |> should.be_true
              "{\"source\":"
              <> json.json_quote(source)
              <> ",\"signature\":\"int\"}"
            }
          }
        },
      )
    outcome.attempts |> should.equal(2)
    let assert Ok(before) = namespace.load_current(adapter, "factory")

    let assert Error(message) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        generation_loop.Plan(..plan, max_attempts: 1),
        fn(_) {
          "{\"source\":\"(define generated-number 99)\",\"signature\":\"int\"}"
        },
      )
    string.contains(message, "exhausted 1 attempt") |> should.be_true
    let assert Ok(after) = namespace.load_current(adapter, "factory")
    namespace.names(after) |> should.equal(namespace.names(before))
    namespace.get(after, "generated-number")
    |> should.equal(namespace.get(before, "generated-number"))

    let assert Error(budget_message) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        generation_loop.Plan(..plan, max_attempts: 0),
        fn(_) { panic as "zero attempts must not call the generator" },
      )
    string.contains(budget_message, "attempt") |> should.be_true
  })
}

pub fn signature_mismatch_is_refused_before_publication_test() {
  with_store(fn(adapter, root) {
    let plan =
      generation_loop.Plan(
        template: "generate {{signature}}",
        variables: [],
        signature: ast.Builtin(ast.IntType),
        max_attempts: 1,
        target: None,
      )
    let source =
      "(define wrong-type \"oops\")\n(define test_wrong-type (do Test expect 1))"
    let assert Error(message) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        plan,
        fn(_) {
          "{\"source\":" <> json.json_quote(source) <> ",\"signature\":\"int\"}"
        },
      )
    string.contains(message, "signature") |> should.be_true
    let assert Ok(ns) = namespace.load_current_or_empty(adapter, "factory")
    namespace.names(ns) |> should.equal([])
  })
}

pub fn untrusted_generation_refuses_before_candidate_or_branch_write_test() {
  with_store(fn(adapter, root) {
    let plan =
      generation_loop.Plan(
        template: "generate code",
        variables: [],
        signature: ast.Builtin(ast.IntType),
        max_attempts: 1,
        target: None,
      )
    let assert Error(message) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        True,
        plan,
        fn(_) { panic as "untrusted generation must not call the generator" },
      )
    string.contains(message, "untrusted") |> should.be_true
    let assert Ok(ns) = namespace.load_current_or_empty(adapter, "factory")
    namespace.names(ns) |> should.equal([])
  })
}

pub fn explicit_target_admits_helpers_and_runs_test() {
  with_store(fn(adapter, root) {
    let plan =
      generation_loop.Plan(
        template: "Generate {{signature}} with a local helper",
        variables: [],
        signature: ast.Builtin(ast.IntType),
        max_attempts: 1,
        target: Some("generated-number"),
      )
    let source =
      "(define generated-base 40)\n"
      <> "(define test_generated-base (do Test expect (eq? generated-base 40)))\n"
      <> "(define generated-number (+ generated-base 2))\n"
      <> "(define test_generated-number (do Test expect (eq? generated-number 42)))\n"
    let assert Ok(outcome) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        plan,
        fn(_) {
          "{\"source\":" <> json.json_quote(source) <> ",\"signature\":\"int\"}"
        },
      )
    outcome.publication.admitted |> should.equal(2)
    let assert Ok(helper) = published(outcome.publication, "generated-base")
    let assert Ok(target) = published(outcome.publication, "generated-number")
    helper.content_ref |> should.not_equal(target.content_ref)
    run_ref.run_verified_on_branch(
      adapter,
      ref(target.content_ref),
      "factory",
      [],
      False,
    )
    |> should.equal(Ok("42"))
    let response =
      app_route.request(adapter, "factory", "generated-number", "{\"args\":[]}")
    response.status |> should.equal(200)
    string.contains(response.body, "42") |> should.be_true
  })
}

pub fn invalid_explicit_target_preserves_existing_branch_test() {
  with_store(fn(adapter, root) {
    let baseline =
      "(define stable-number 7)\n"
      <> "(define test_stable-number (do Test expect (eq? stable-number 7)))\n"
    let assert Ok(_) =
      agent_publish.publish_source(adapter, baseline, "factory", False, root)
    let assert Ok(before) = namespace.load_current(adapter, "factory")
    let plan =
      generation_loop.Plan(
        template: "Generate {{signature}} with a helper",
        variables: [],
        signature: ast.Builtin(ast.IntType),
        max_attempts: 1,
        target: Some("generated-number"),
      )
    let missing_source =
      "(define generated-base 40)\n"
      <> "(define test_generated-base (do Test expect (eq? generated-base 40)))\n"
    let assert Error(missing) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        plan,
        fn(_) {
          "{\"source\":"
          <> json.json_quote(missing_source)
          <> ",\"signature\":\"int\"}"
        },
      )
    string.contains(missing, "target") |> should.be_true
    let assert Ok(after_missing) = namespace.load_current(adapter, "factory")
    namespace.names(after_missing) |> should.equal(namespace.names(before))

    let wrong_source =
      "(define generated-base 40)\n"
      <> "(define test_generated-base (do Test expect (eq? generated-base 40)))\n"
      <> "(define generated-number \"wrong\")\n"
      <> "(define test_generated-number (do Test expect (eq? generated-number \"wrong\")))\n"
    let assert Error(wrong_type) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        plan,
        fn(_) {
          "{\"source\":"
          <> json.json_quote(wrong_source)
          <> ",\"signature\":\"int\"}"
        },
      )
    string.contains(wrong_type, "signature mismatch") |> should.be_true
    let assert Ok(after_wrong) = namespace.load_current(adapter, "factory")
    namespace.names(after_wrong) |> should.equal(namespace.names(before))
    namespace.get(after_wrong, "stable-number")
    |> should.equal(namespace.get(before, "stable-number"))
  })
}

pub fn patch_reports_dependents_without_rewriting_stored_code_test() {
  with_store(fn(adapter, root) {
    let source =
      "(define base-value 1)\n"
      <> "(define test_base-value (do Test expect 1))\n"
      <> "(define derived-value base-value)\n"
      <> "(define test_derived-value (do Test expect 1))\n"
    let assert Ok(initial) =
      agent_publish.publish_source(adapter, source, "factory", False, root)
    let assert Ok(derived) = published(initial, "derived-value")
    let updated_source =
      "(define base-value 2)\n(define test_base-value (do Test expect 1))\n"
    let assert Ok(outcome) =
      generation_loop.generate_and_publish(
        adapter,
        root,
        "factory",
        False,
        generation_loop.Plan(
          template: "replace base with {{signature}}",
          variables: [],
          signature: ast.Builtin(ast.IntType),
          max_attempts: 1,
          target: None,
        ),
        fn(_) {
          "{\"source\":"
          <> json.json_quote(updated_source)
          <> ",\"signature\":\"int\"}"
        },
      )
    outcome.dependents |> should.equal(["derived-value"])
    let assert Ok(ns) = namespace.load_current(adapter, "factory")
    let assert Ok(current_derived) = namespace.get(ns, "derived-value")
    current_derived |> should.equal(ref(derived.content_ref))
    run_ref.run_verified_on_branch(
      adapter,
      current_derived,
      "factory",
      [],
      False,
    )
    |> should.equal(Ok("2"))
  })
}

fn text_to_text() -> ast.Type {
  ast.Fn(
    params: [ast.Builtin(ast.TextType)],
    result: ast.Builtin(ast.TextType),
    requires: ast.Required([]),
  )
}

fn published(
  publication: agent_publish.Publication,
  name: String,
) -> Result(agent_publish.Published, Nil) {
  list.find(publication.definitions, fn(item) { item.name == name })
}

fn ref(hex: String) -> identity.DefinitionRef {
  let assert Ok(value) = identity.parse_ref_hex(hex)
  value
}

fn with_store(work: fn(storage.StorageAdapter, String) -> a) -> a {
  let root = "/tmp/gleamunison-generation-loop-test"
  let path = root <> "/store.dets"
  let _ = storage.dets_delete_file(path)
  let assert Ok(_) = simplifile.create_directory_all(root)
  envoy.set("GLEAMUNISON_EVIDENCE_SIGNING_KEY", "generation-loop-test-key")
  let result =
    without_active_storage(fn() {
      let assert Ok(adapter) = storage.dets(path)
      work(adapter, root)
    })
  envoy.unset("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  let _ = storage.dets_delete_file(path)
  result
}
