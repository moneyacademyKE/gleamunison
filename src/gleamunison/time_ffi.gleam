//// One declaration for the timer external.
////
//// `timer:sleep/1` was declared twice — once by the watch loop, once by the
//// retry middleware — because two callers needed a pause and neither had an
//// owner to ask. This module depends on nothing, so both can.

/// Block the calling process for `ms` milliseconds.
@external(erlang, "timer", "sleep")
pub fn sleep(ms: Int) -> Nil
