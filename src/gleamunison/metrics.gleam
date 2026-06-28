@external(erlang, "gleamunison_metrics", "counter")
pub fn counter(name: String, delta: Int) -> Nil

@external(erlang, "gleamunison_metrics", "gauge")
pub fn gauge(name: String, value: Float) -> Nil

@external(erlang, "gleamunison_metrics", "histogram")
pub fn histogram(name: String, value: Float) -> Nil
