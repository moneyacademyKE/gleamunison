import gleam/string
import gleamunison/datetime
import gleeunit/should

pub fn unix_epoch_renders_as_second_precision_zulu_test() {
  datetime.format_unix(0) |> should.equal("1970-01-01T00:00:00Z")
}

pub fn a_known_timestamp_preserves_the_existing_rendering_test() {
  datetime.format_unix(1_767_225_600)
  |> should.equal("2026-01-01T00:00:00Z")
}

pub fn the_current_unix_time_renders_without_fractional_seconds_test() {
  let rendered = datetime.format_unix(datetime.now_unix())
  string.length(rendered) |> should.equal(20)
  string.ends_with(rendered, "Z") |> should.be_true
}
