import gleamunison/cli_result
import gleeunit/should

pub fn a_coded_success_returns_after_printing_test() {
  cli_result.print_coded(Ok("coded result: ✓\nsecond line"))
  |> should.equal(Nil)
}
