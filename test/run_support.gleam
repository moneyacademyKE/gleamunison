//// Test-only shortcuts around the surviving run_ref authority.
////
//// Production callers state the branch and evidence decision explicitly.
//// Tests that are exercising storage, arity, rendering, or effects rather
//// than the evidence gate use the default branch and the local-store
//// escape hatch.

import gleam/dynamic.{type Dynamic}
import gleamunison/identity.{type DefinitionRef}
import gleamunison/run_error.{type RunError}
import gleamunison/run_ref
import gleamunison/storage.{type StorageAdapter}

pub fn run(
  adapter: StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
) -> Result(String, RunError) {
  run_ref.run_verified_on_branch(
    adapter,
    ref,
    run_ref.default_branch,
    args,
    True,
  )
}

pub fn run_on_branch(
  adapter: StorageAdapter,
  ref: DefinitionRef,
  branch: String,
  args: List(Dynamic),
) -> Result(String, RunError) {
  run_ref.run_verified_on_branch(adapter, ref, branch, args, True)
}

pub fn run_raw(
  adapter: StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
) -> Result(Dynamic, RunError) {
  run_ref.run_verified_raw_on_branch(
    adapter,
    ref,
    run_ref.default_branch,
    args,
    True,
  )
}

pub fn run_verified(
  adapter: StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
  allow_unverified: Bool,
) -> Result(String, RunError) {
  run_ref.run_verified_on_branch(
    adapter,
    ref,
    run_ref.default_branch,
    args,
    allow_unverified,
  )
}

pub fn run_verified_raw(
  adapter: StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
  allow_unverified: Bool,
) -> Result(Dynamic, RunError) {
  run_ref.run_verified_raw_on_branch(
    adapter,
    ref,
    run_ref.default_branch,
    args,
    allow_unverified,
  )
}

pub fn inspect_function(
  adapter: StorageAdapter,
  ref: DefinitionRef,
) -> Result(run_ref.FunctionInfo, RunError) {
  run_ref.inspect_function_on_branch(adapter, ref, run_ref.default_branch)
}
