import gleamunison/evidence
import gleamunison/storage
import gleamunison/turnstile

fn adapter() {
  storage.inmemory()
}

pub fn missing_evidence_is_refused_test() {
  let a = adapter()
  let defs = [#("parse-json", "abc123", False), #("render", "def456", False)]
  let assert Error(missing) = turnstile.check(a, defs)
  assert missing == ["parse-json", "render"]
}

pub fn passing_evidence_admits_test() {
  let a = adapter()
  let assert Ok(_) =
    evidence.attach(
      a,
      subject: "abc123",
      kind: evidence.Test,
      verdict: "pass",
      payload: "test_parse-json: 3 passed, 0 failed",
      ts: 1000,
    )
  let assert Ok(_) =
    evidence.attach(
      a,
      subject: "def456",
      kind: evidence.Test,
      verdict: "pass",
      payload: "test_render: 1 passed, 0 failed",
      ts: 1001,
    )
  let assert Ok(passed) =
    turnstile.check(a, [
      #("parse-json", "abc123", False),
      #("render", "def456", False),
    ])
  assert passed == ["parse-json", "render"]
}

pub fn failing_verdict_is_not_evidence_test() {
  let a = adapter()
  let assert Ok(_) =
    evidence.attach(
      a,
      subject: "abc123",
      kind: evidence.Test,
      verdict: "fail",
      payload: "test_parse-json: 1 passed, 2 failed",
      ts: 1000,
    )
  let assert Error(missing) =
    turnstile.check(a, [#("parse-json", "abc123", False)])
  assert missing == ["parse-json"]
}

pub fn mixed_batch_names_exactly_the_unevidenced_test() {
  let a = adapter()
  let assert Ok(_) =
    evidence.attach(
      a,
      subject: "good",
      kind: evidence.Test,
      verdict: "pass",
      payload: "ok",
      ts: 1,
    )
  let assert Error(missing) =
    turnstile.check(a, [
      #("good", "good", False),
      #("bad", "bad", False),
      #("ugly", "ugly", False),
    ])
  assert missing == ["bad", "ugly"]
}

pub fn test_defs_are_not_gated_test() {
  // Test defs produce evidence; requiring evidence FOR them is a
  // chicken-and-egg loop. The turnstile excludes them by name prefix.
  let a = adapter()
  let assert Error(missing) =
    turnstile.check(a, [
      #("test_parse-json", "anyhash", False),
      #("parse-json", "none", False),
    ])
  assert missing == ["parse-json"]
}

pub fn all_test_defs_pass_the_gate_test() {
  let a = adapter()
  let assert Ok(passed) =
    turnstile.check(a, [#("test_a", "h1", False), #("test_b", "h2", False)])
  assert passed == ["test_a", "test_b"]
}

/// Effectful defs can be admitted by human Io attestation: the only honest
/// evidence for IO a suite cannot drive.
pub fn io_attestation_admits_effectful_def_test() {
  let a = adapter()
  let assert Ok(_) =
    evidence.attach(
      a,
      subject: "gamehash",
      kind: evidence.Io,
      verdict: "approved",
      payload: "played it; win and EOF paths work",
      ts: 1,
    )
  let assert Ok(passed) = turnstile.check(a, [#("main", "gamehash", True)])
  assert passed == ["main"]
}

/// A pure def can never slip past the gate on Io attestation alone: tests
/// are cheap for pure code, so they are mandatory.
pub fn io_attestation_never_admits_pure_def_test() {
  let a = adapter()
  let assert Ok(_) =
    evidence.attach(
      a,
      subject: "purehash",
      kind: evidence.Io,
      verdict: "approved",
      payload: "trust me",
      ts: 1,
    )
  let assert Error(missing) =
    turnstile.check(a, [#("verdict", "purehash", False)])
  assert missing == ["verdict"]
}

/// Effectfulness alone is not evidence: an effectful def with no
/// attestation of any kind is still refused.
pub fn effectful_without_evidence_is_refused_test() {
  let a = adapter()
  let assert Error(missing) = turnstile.check(a, [#("main", "nope", True)])
  assert missing == ["main"]
}
