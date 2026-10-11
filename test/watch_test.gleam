import gleamunison/cli_watch.{Changed, Missing, Unchanged}
import simplifile

pub fn poll_detects_change_test() {
  let path = "/tmp/watch_poll_test.lisp"
  let assert Ok(Nil) = simplifile.write(path, "(define a 1)\n")
  // Never seen before: mtime 0 → Changed with the file's real mtime.
  let assert Changed(mtime) = cli_watch.poll(path, 0)
  let assert True = mtime > 0
  // Same mtime: unchanged.
  let assert Unchanged = cli_watch.poll(path, mtime)
  simplifile.delete(path)
}

pub fn poll_missing_file_test() {
  let assert Missing = cli_watch.poll("/tmp/watch_poll_nonexistent_xyz", 0)
}
