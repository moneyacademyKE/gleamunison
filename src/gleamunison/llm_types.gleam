//// Shared data vocabulary for the LLM boundary.
////
//// Types only — no behaviour. llm.gleam (ability host) and llm_wire.gleam
//// (provider wire codec) both depend on this vocabulary; keeping the data
//// in its own module keeps that dependency acyclic (Gleam has no re-export,
//// so consumers name the module that owns the data).

pub type Role {
  System
  User
  Assistant
}

pub type Message {
  Message(role: Role, content: String)
}

pub type Completion {
  Completion(
    content: String,
    model: String,
    input_tokens: Int,
    output_tokens: Int,
  )
}

pub type LlmError {
  TransportError(reason: String)
  HttpError(status: Int, body: String)
  DecodeError(reason: String)
}

pub type Provider {
  OpenAI
  Anthropic
}

pub type ProviderConfig {
  ProviderConfig(
    provider: Provider,
    base_url: String,
    api_key: String,
    model: String,
    max_tokens: Int,
    timeout_ms: Int,
    /// OpenAI-compatible reasoning effort ("low"/"medium"/"high"/"max").
    /// Empty string = omit from the request (provider default).
    reasoning_effort: String,
  )
}
