import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleamunison/crypto
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_bytes, hash_equal, hash_to_debug_string,
}
import gleamunison/storage.{type StorageAdapter}

@external(erlang, "gleamunison_config", "get_env")
fn get_env(key: String) -> Result(String, Nil)

/// What kind of evidence this is. Deploy gates ask for these by name.
pub type Kind {
  Test
  Review
  PropertyCheck
  /// Human attestation that an effectful definition behaves: "I ran it and
  /// it worked." The only honest evidence for IO a suite cannot drive.
  Io
}

/// A fact about a definition hash, stored as a CAS chunk. The chunk's own
/// hash is the evidence identity; the subject is the hash it attests to.
pub type Evidence {
  Evidence(
    subject: String,
    kind: Kind,
    verdict: String,
    payload: String,
    ts: Int,
    signer: String,
    signature: String,
  )
}

pub type Signer {
  Signer(id: String, secret: BitArray)
}

/// Construct a local signer. The secret remains in memory and is never
/// serialized into evidence; only the stable signer id and HMAC are stored.
pub fn signer(id: String, secret: BitArray) -> Signer {
  Signer(id, secret)
}

pub type VerificationPolicy {
  /// Compatibility mode for in-memory/unit fixtures only.
  AllowUnsigned
  /// Production mode: only a matching signer id and HMAC can admit evidence.
  RequireTrusted(List(Signer))
}

pub fn allow_unsigned() -> VerificationPolicy {
  AllowUnsigned
}

pub fn require_signer(signer: Signer) -> VerificationPolicy {
  RequireTrusted([signer])
}

pub type AttachError {
  StoreFailed(String)
}

pub fn production_signer() -> Result(Signer, String) {
  case get_env("GLEAMUNISON_EVIDENCE_SIGNING_KEY") {
    Ok(secret) if secret != "" ->
      Ok(signer(
        "env:GLEAMUNISON_EVIDENCE_SIGNING_KEY",
        bit_array.from_string(secret),
      ))
    _ ->
      Error(
        "evidence: GLEAMUNISON_EVIDENCE_SIGNING_KEY is required for production verification",
      )
  }
}

pub fn production_policy() -> Result(VerificationPolicy, String) {
  production_signer() |> result.map(require_signer)
}

fn kind_tag(k: Kind) -> String {
  case k {
    Test -> "test"
    Review -> "review"
    PropertyCheck -> "property"
    Io -> "io"
  }
}

/// Public name for a kind — reports, CLIs, and MCP tools all render the
/// same word.
pub fn kind_name(k: Kind) -> String {
  kind_tag(k)
}

fn tag_kind(s: String) -> Result(Kind, Nil) {
  case s {
    "test" -> Ok(Test)
    "review" -> Ok(Review)
    "property" -> Ok(PropertyCheck)
    "io" -> Ok(Io)
    _ -> Error(Nil)
  }
}

fn encode_text(value: String) -> String {
  bit_array.base64_encode(bit_array.from_string(value), True)
}

fn decode_text(value: String) -> Result(String, Nil) {
  use bytes <- result.try(
    bit_array.base64_decode(value) |> result.replace_error(Nil),
  )
  bit_array.to_string(bytes) |> result.replace_error(Nil)
}

/// Canonical serialization. All free text is base64, so parsing is
/// unambiguous even when a note contains delimiters or newlines.
fn serialize(e: Evidence) -> BitArray {
  bit_array.from_string(string.join(
    [
      "evidence",
      "1",
      encode_text(e.subject),
      kind_tag(e.kind),
      int.to_string(e.ts),
      encode_text(e.signer),
      e.signature,
      encode_text(e.verdict),
      encode_text(e.payload),
    ],
    ":",
  ))
}

fn parse(bytes: BitArray) -> Result(Evidence, Nil) {
  use text <- result.try(
    bit_array.to_string(bytes) |> result.replace_error(Nil),
  )
  case string.split(text, ":") {
    [
      "evidence",
      "1",
      subject_b64,
      tag,
      ts_s,
      signer_b64,
      signature,
      verdict_b64,
      payload_b64,
    ] -> {
      use subject <- result.try(decode_text(subject_b64))
      use kind <- result.try(tag_kind(tag))
      use ts <- result.try(int.parse(ts_s) |> result.replace_error(Nil))
      use signer <- result.try(decode_text(signer_b64))
      use verdict <- result.try(decode_text(verdict_b64))
      use payload <- result.try(decode_text(payload_b64))
      Ok(Evidence(subject, kind, verdict, payload, ts, signer, signature))
    }
    _ -> Error(Nil)
  }
}

fn signer_id(signer: Signer) -> String {
  let Signer(id, _) = signer
  id
}

fn signer_secret(signer: Signer) -> BitArray {
  let Signer(_, secret) = signer
  secret
}

/// The signature binds every admitted field, including signer identity.
fn signature_input(e: Evidence) -> BitArray {
  bit_array.from_string(string.join(
    [
      "evidence",
      "1",
      encode_text(e.subject),
      kind_tag(e.kind),
      int.to_string(e.ts),
      encode_text(e.signer),
      encode_text(e.verdict),
      encode_text(e.payload),
    ],
    ":",
  ))
}

fn signature_for(signer: Signer, e: Evidence) -> String {
  case crypto.hmac(crypto.Sha256, signer_secret(signer), signature_input(e)) {
    Ok(bytes) -> crypto.to_hex(bytes)
    Error(_) -> ""
  }
}

/// Create an identity-bearing evidence record.
pub fn sign(
  signer: Signer,
  subject: String,
  kind: Kind,
  verdict: String,
  payload: String,
  ts: Int,
) -> Evidence {
  let unsigned =
    Evidence(subject, kind, verdict, payload, ts, signer_id(signer), "")
  Evidence(
    unsigned.subject,
    unsigned.kind,
    unsigned.verdict,
    unsigned.payload,
    unsigned.ts,
    unsigned.signer,
    signature_for(signer, unsigned),
  )
}

fn trusted(e: Evidence, policy: VerificationPolicy) -> Bool {
  case policy {
    AllowUnsigned -> e.signer == "" && e.signature == ""
    RequireTrusted(signers) ->
      list.any(signers, fn(signer) {
        signer_id(signer) == e.signer
        && e.signature != ""
        && crypto.secure_compare(
          bit_array.from_string(e.signature),
          bit_array.from_string(signature_for(signer, e)),
        )
      })
  }
}

fn ref_hash(ref: DefinitionRef) {
  let Ref(h) = ref
  h
}

fn attach_record(
  adapter: StorageAdapter,
  e: Evidence,
) -> Result(#(DefinitionRef, String), AttachError) {
  let bytes = serialize(e)
  let ref = Ref(hash_bytes(bytes))
  case adapter.insert(ref, bytes) {
    Ok(Nil) -> Ok(#(ref, hash_to_debug_string(ref_hash(ref))))
    Error(_) -> Error(StoreFailed("evidence chunk insert failed"))
  }
}

/// Legacy local fixture helper. Production callers must use attach_signed.
pub fn attach(
  adapter: StorageAdapter,
  subject subject: String,
  kind kind: Kind,
  verdict verdict: String,
  payload payload: String,
  ts ts: Int,
) -> Result(#(DefinitionRef, String), AttachError) {
  attach_record(adapter, Evidence(subject, kind, verdict, payload, ts, "", ""))
}

/// Store signed evidence. The secret itself is never serialized.
pub fn attach_signed(
  adapter: StorageAdapter,
  signer signer: Signer,
  subject subject: String,
  kind kind: Kind,
  verdict verdict: String,
  payload payload: String,
  ts ts: Int,
) -> Result(#(DefinitionRef, String), AttachError) {
  attach_record(adapter, sign(signer, subject, kind, verdict, payload, ts))
}

/// Every well-formed, untampered evidence record for a subject hash.
/// Tampered chunks and non-evidence chunks are silently excluded.
pub fn for_subject(adapter: StorageAdapter, subject: String) -> List(Evidence) {
  case adapter.list_refs() {
    Error(_) -> []
    Ok(refs) ->
      list.filter_map(refs, fn(ref) {
        case adapter.lookup(ref) {
          Ok(Some(bytes)) -> {
            let Ref(h) = ref
            case hash_equal(hash_bytes(bytes), h) {
              False -> Error(Nil)
              True ->
                case parse(bytes) {
                  Ok(e) if e.subject == subject -> Ok(e)
                  _ -> Error(Nil)
                }
            }
          }
          _ -> Error(Nil)
        }
      })
  }
}

pub fn verified_with_policy(
  adapter: StorageAdapter,
  subject: String,
  kind: Kind,
  policy: VerificationPolicy,
) -> Bool {
  for_subject(adapter, subject)
  |> list.any(fn(e) {
    e.kind == kind
    && { e.verdict == "pass" || e.verdict == "approved" }
    && trusted(e, policy)
  })
}

/// Constant-time hex comparison for signature checks outside this module.
pub fn secure_compare_hex(a: String, b: String) -> Bool {
  crypto.secure_compare(bit_array.from_string(a), bit_array.from_string(b))
}

/// Compatibility helper for local fixtures. Production/package gates should
/// call verified_with_policy with RequireTrusted.
pub fn verified(adapter: StorageAdapter, subject: String, kind: Kind) -> Bool {
  verified_with_policy(adapter, subject, kind, AllowUnsigned)
}
