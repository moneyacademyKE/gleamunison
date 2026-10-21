import gleam/int
import gleam/list
import gleam/string
import gleamunison/log

pub type HealthStatus {
  Healthy(String)
  Degraded(String)
  Unhealthy(String)
}

pub type HealthCheck {
  HealthCheck(name: String, check: fn() -> Bool, description: String)
}

@external(erlang, "gleamunison_health", "node_status")
fn ffi_node_status() -> #(String, Int, Int)

pub fn run_checks(checks: List(HealthCheck)) -> HealthStatus {
  let total = list.length(checks)
  let results =
    list.map(checks, fn(check) {
      let ok = check.check()
      case ok {
        True -> #(check.name, True, check.description)
        False -> #(check.name, False, check.description)
      }
    })
  let failures = list.filter(results, fn(r) { !r.1 })
  let failed_count = list.length(failures)
  case failed_count {
    0 -> {
      let #(node, _, mem) = ffi_node_status()
      Healthy(
        "node=" <> node <> " memory_mb=" <> int.to_string(mem) <> " checks=ok",
      )
    }
    _ if failed_count == total -> {
      let failed_names =
        list.map(failures, fn(f) { f.0 })
        |> string.join(", ")
      log.warn("Health check failures: " <> failed_names)
      Unhealthy("Failed checks: " <> failed_names)
    }
    _ -> {
      let failed_names =
        list.map(failures, fn(f) { f.0 })
        |> string.join(", ")
      let passed = total - failed_count
      log.warn(
        "Health check partial failure ("
        <> int.to_string(passed)
        <> "/"
        <> int.to_string(total)
        <> "): "
        <> failed_names,
      )
      Degraded(
        "Passed "
        <> int.to_string(passed)
        <> "/"
        <> int.to_string(total)
        <> ", failed: "
        <> failed_names,
      )
    }
  }
}

@external(erlang, "gleamunison_readiness", "ready")
pub fn readiness() -> Bool
