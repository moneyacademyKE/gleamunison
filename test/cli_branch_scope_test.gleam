//// `--branch` names the namespace a run resolves dependency names through. A
//// branch that does not exist must not read as "no bindings": a typo would
//// silently select an empty namespace, and a definition that needs no name
//// refs would run as though the branch had been applied. An explicit branch is
//// a resolution the caller asked for, so its absence is exit 2, not a shrug.

import gleam/option.{None, Some}
import gleam/string
import gleamunison/cli_result
import gleamunison/cli_run
import gleamunison/identity.{type DefinitionRef, Ref, hash_bytes}
import gleamunison/namespace
import gleamunison/storage
import gleeunit/should

fn ref_tag(tag: String) -> DefinitionRef {
  Ref(hash_bytes(<<tag:utf8>>))
}

fn store_with_branch(branch: String, name: String, content: DefinitionRef) {
  let adapter = storage.inmemory()
  let ns = namespace.empty() |> namespace.set(name, content)
  let assert Ok(_) = namespace.commit(adapter, branch, ns)
  adapter
}

/// No `--branch`: the default namespace is optional, because a fresh store has
/// none and a self-contained definition still runs.
pub fn default_branch_has_no_note_test() {
  let adapter = storage.inmemory()
  cli_run.branch_scope_note(adapter, None, ref_tag("any"))
  |> should.equal(Ok(None))
}

/// An explicit branch that exists and binds the content says nothing.
pub fn bound_branch_has_no_note_test() {
  let target = ref_tag("content")
  let adapter = store_with_branch("dev", "shout", target)
  cli_run.branch_scope_note(adapter, Some("dev"), target)
  |> should.equal(Ok(None))
}

/// An explicit branch nobody committed is a resolution failure, not an empty
/// namespace. The exit code a script reads must say "no such branch".
pub fn missing_branch_is_unresolvable_test() {
  let adapter = storage.inmemory()
  case cli_run.branch_scope_note(adapter, Some("devv"), ref_tag("content")) {
    Ok(_) -> panic as "a typo'd branch was accepted"
    Error(#(code, message)) -> {
      code |> should.equal(cli_result.unresolvable)
      string.contains(message, "no such branch: devv")
      |> should.be_true
    }
  }
}

/// Content is branch-independent: the hash IS the content, so running it on a
/// branch that does not bind it is legitimate — but it must not be silent,
/// because the caller may believe `--branch` selected a version of the target.
pub fn unbound_target_is_reported_test() {
  let other = ref_tag("something-else")
  let adapter = store_with_branch("dev", "other", other)
  case cli_run.branch_scope_note(adapter, Some("dev"), ref_tag("target")) {
    Ok(Some(note)) -> {
      string.contains(note, "not bound on branch dev")
      |> should.be_true
      string.contains(note, "the hash is the content")
      |> should.be_true
    }
    Ok(None) -> panic as "expected a warning, got none"
    Error(_) -> panic as "expected a warning, got a refusal"
  }
}

/// The CLI form only prints; it never fails a run whose branch exists.
pub fn preflight_prints_and_passes_test() {
  let other = ref_tag("something-else")
  let adapter = store_with_branch("dev", "other", other)
  cli_run.preflight_branch(adapter, Some("dev"), ref_tag("target"))
  |> should.equal(Ok(Nil))
}
