import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_bytes, hash_equal, hash_to_debug_string,
}
import gleamunison/storage.{type StorageAdapter}

/// What kind of evidence this is. Deploy gates ask for these by name.
pub type Kind {
  Test
  Review
  PropertyCheck
  /// Human attestation that an effectful definition behaves: "I ran it and
  /// it worked." The only honest evidence for IO a suite cannot drive —
  /// and never a substitute for Test on pure defs.
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
  )
}

pub type AttachError {
  StoreFailed(String)
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

/// Canonical serialization. Verdict and payload are base64 so the format
/// is delimiter-safe and roundtrips any bytes.
fn serialize(e: Evidence) -> BitArray {
  let line =
    string.join(
      [
        "evidence",
        "1",
        e.subject,
        kind_tag(e.kind),
        int.to_string(e.ts),
        bit_array.base64_encode(bit_array.from_string(e.verdict), True),
        bit_array.base64_encode(bit_array.from_string(e.payload), True),
      ],
      ":",
    )
  bit_array.from_string(line)
}

fn parse(bytes: BitArray) -> Result(Evidence, Nil) {
  use text <- result.try(
    bit_array.to_string(bytes) |> result.replace_error(Nil),
  )
  case string.split(text, ":") {
    ["evidence", "1", subject, tag, ts_s, verdict_b64, payload_b64] -> {
      use kind <- result.try(tag_kind(tag))
      use ts <- result.try(int.parse(ts_s) |> result.replace_error(Nil))
      use verdict_bits <- result.try(
        bit_array.base64_decode(verdict_b64) |> result.replace_error(Nil),
      )
      use payload_bits <- result.try(
        bit_array.base64_decode(payload_b64) |> result.replace_error(Nil),
      )
      use verdict <- result.try(
        bit_array.to_string(verdict_bits) |> result.replace_error(Nil),
      )
      use payload <- result.try(
        bit_array.to_string(payload_bits) |> result.replace_error(Nil),
      )
      Ok(Evidence(subject, kind, verdict, payload, ts))
    }
    _ -> Error(Nil)
  }
}

/// Store an evidence record. Returns the evidence ref and its hex hash.
pub fn attach(
  adapter: StorageAdapter,
  subject subject: String,
  kind kind: Kind,
  verdict verdict: String,
  payload payload: String,
  ts ts: Int,
) -> Result(#(DefinitionRef, String), AttachError) {
  let bytes = serialize(Evidence(subject, kind, verdict, payload, ts))
  let ref = Ref(hash_bytes(bytes))
  case adapter.insert(ref, bytes) {
    Ok(Nil) -> Ok(#(ref, hash_to_debug_string(ref_hash(ref))))
    Error(_) -> Error(StoreFailed("evidence chunk insert failed"))
  }
}

fn ref_hash(ref: DefinitionRef) {
  let Ref(h) = ref
  h
}

/// Every well-formed, untampered evidence record for a subject hash.
/// Tampered chunks (content hash ≠ ref hash) and non-evidence chunks are
/// silently excluded: evidence is only meaningful when integrity holds.
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
                  Ok(e) ->
                    case e.subject == subject {
                      True -> Ok(e)
                      False -> Error(Nil)
                    }
                  Error(_) -> Error(Nil)
                }
            }
          }
          _ -> Error(Nil)
        }
      })
  }
}

/// Is there at least one passing attestation of this kind for the subject?
/// Passing verdicts are explicit: "pass" for tests/properties, "approved"
/// for reviews. Anything else is not verification.
pub fn verified(adapter: StorageAdapter, subject: String, kind: Kind) -> Bool {
  for_subject(adapter, subject)
  |> list.any(fn(e) {
    e.kind == kind && { e.verdict == "pass" || e.verdict == "approved" }
  })
}
