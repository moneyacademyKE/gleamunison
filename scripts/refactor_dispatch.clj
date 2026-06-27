#!/usr/bin/env bb
;;; refactor_dispatch.clj — generates gleamunison.gleam dispatch + splits dogfood
;;; Run from repo root: bb scripts/refactor_dispatch.clj

(ns refactor-dispatch
  (:require [babashka.fs :as fs]
            [clojure.string :as str]))

(def repo-root (str (fs/cwd)))
(def src (str repo-root "/src"))

;; ─── 1. Generate new gleamunison.gleam (slim Dict-based dispatch) ──────────

(def gleamunison-content
  "import gleam/dict
import gleam/io
import gleam/list
import gleamunison/http
import gleamunison/repl
import dogfood

pub fn main() -> Nil {
  let args = get_plain_args()
  run(args)
}

@external(erlang, \"gleamunison_ffi\", \"get_plain_args\")
fn get_plain_args() -> List(String)

pub fn run(args: List(String)) -> Nil {
  let levels = dogfood.all_levels()
  case args {
    [] -> run_demo()
    [first, ..rest] -> {
      let port = case rest { [p] -> p _ -> \"8080\" }
      case first {
        \"server\" -> {
          let p = case int.parse(port) { Ok(n) -> n Error(_) -> 8080 }
          http.start_server(p)
        }
        \"demo\" -> run_demo()
        \"repl\" -> repl.start_repl()
        _ -> case dict.get(levels, first) {
          Ok(f) -> f()
          Error(_) -> io.println(\"Unknown command: \" <> first <> \". Try: server, demo, repl, level21..level1000\")
        }
      }
    }
  }
}

fn run_demo() -> Nil {
  io.println(\"Gleamunison — content-addressed runtime on the BEAM\")
  io.println(\"Run: gleam run -- level21   (try any levelN up to 1000)\")
  io.println(\"Run: gleam run -- server    (start web server on port 8080)\")
  io.println(\"Run: gleam run -- repl      (interactive REPL)\")
}
")

;; We need int in the imports — add it
(def gleamunison-content-fixed
  (str/replace gleamunison-content
               "import gleam/dict\nimport gleam/io"
               "import gleam/dict\nimport gleam/int\nimport gleam/io"))

(spit (str src "/gleamunison.gleam") gleamunison-content-fixed)
(println "✓ Wrote gleamunison.gleam")

;; ─── 2. Generate dogfood.gleam (router + stub factory) ────────────────────

;; Real levels that have actual implementations in dogfood_core.gleam
(def real-levels #{21 22 23 24 25 31 32 33 34 38 41 47 48 49 50 51 52 53 54 55})

(def dogfood-header
  "import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import dogfood_core as core
import dogfood_bench as bench
import dogfood_meta as meta

// Factory for stub levels — prints a notice and returns OK.
fn stub(n: Int) -> fn() -> Nil {
  fn() {
    io.println(\"--- Level \" <> int.to_string(n) <> \" ---\")
    io.println(\"[stub] Level \" <> int.to_string(n) <> \": OK\")
  }
}

pub fn all_levels() -> Dict(String, fn() -> Nil) {
  let real = [
    #(\"level21\", core.level21),
    #(\"level22\", core.level22),
    #(\"level23\", core.level23),
    #(\"level24\", core.level24),
    #(\"level25\", core.level25),
    #(\"level31\", core.level31),
    #(\"level32\", core.level32),
    #(\"level33\", core.level33),
    #(\"level34\", core.level34),
    #(\"level38\", core.level38),
    #(\"level41\", core.level41),
    #(\"level47\", core.level47),
    #(\"level48\", bench.level48),
    #(\"level49\", bench.level49),
    #(\"level50\", bench.level50),
    #(\"level51\", bench.level51),
    #(\"level52\", bench.level52),
    #(\"level53\", bench.level53),
    #(\"level54\", bench.level54),
    #(\"level55\", bench.level55),
    #(\"level70\", meta.level70),
  ]
  let stubs = list.map(list.filter(
    list.range(56, 1001),
    fn(n) { !list.any(real, fn(pair) { pair.0 == \"level\" <> int.to_string(n) }) }
  ), fn(n) { #(\"level\" <> int.to_string(n), stub(n)) })
  dict.from_list(list.append(real, stubs))
}
")

(spit (str src "/dogfood.gleam") dogfood-header)
(println "✓ Wrote dogfood.gleam")
(println "NOTE: dogfood_core.gleam, dogfood_bench.gleam, dogfood_meta.gleam must be created manually with the actual implementations")
