import gleeunit/should

@external(erlang, "gleamunison_metrics_test", "histogram_entries")
fn histogram_entries() -> Int

@external(erlang, "gleamunison_metrics_test", "counter_survives_creator")
fn counter_survives_creator() -> Bool

@external(erlang, "gleamunison_metrics_test", "counter_accumulates")
fn counter_accumulates() -> Bool

@external(erlang, "gleamunison_metrics_test", "supervisor_recovers_owner")
fn supervisor_recovers_owner() -> Bool

@external(erlang, "gleamunison_metrics_test", "registry_is_bounded")
fn registry_is_bounded() -> Bool

pub fn histogram_storage_retains_only_latest_bounded_samples_test() {
  let retained = histogram_entries()
  should.be_true(retained > 0 && retained <= 128)
}

pub fn metrics_survive_short_lived_callers_test() {
  counter_survives_creator() |> should.be_true
}

pub fn counters_accumulate_without_dropping_updates_test() {
  counter_accumulates() |> should.be_true
}

pub fn supervised_metrics_owner_restarts_test() {
  supervisor_recovers_owner() |> should.be_true
}

pub fn metric_cardinality_and_names_are_bounded_test() {
  registry_is_bounded() |> should.be_true
}
