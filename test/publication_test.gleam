import gleamunison/ast
import gleamunison/publication
import gleeunit/should

pub fn missing_evidence_description_names_subjects_test() {
  let definition = ast.TermDef(term: ast.Int(1), typ: ast.Builtin(ast.IntType))
  let missing = [publication.Subject("main", "abc123", definition)]

  publication.describe_error(publication.MissingEvidence(missing))
  |> should.equal(
    "publish: REFUSED — no evidence for: main; run tests or attest the named content hashes",
  )
}

pub fn failed_description_passes_reason_through_test() {
  publication.describe_error(publication.Failed(
    "cannot commit namespace: bad head",
  ))
  |> should.equal("cannot commit namespace: bad head")
}
