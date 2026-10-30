//// Golden atoms for the unified DETS/Mnesia table naming (bk-0249).
////
//// The three naming sites (app_db, store_log, storage) now share
//// gleamunison_table_name:stable/4, but their output atoms are load-bearing
//// on disk — Mnesia persists table names in its schema — so every constant
//// below was captured from the PRE-unification code and must never change.
//// If one of these assertions fails, live tables would be orphaned.

import gleeunit/should

@external(erlang, "gleamunison_ffi_test", "app_db_table_name_probe")
fn app_db_name(path: String) -> String

@external(erlang, "gleamunison_ffi_test", "store_log_table_name_probe")
fn store_log_name(path: String) -> String

@external(erlang, "gleamunison_ffi_test", "storage_table_name_probe")
fn storage_name(material: String) -> String

pub fn app_db_table_name_golden_test() {
  app_db_name("/tmp/gleamunison-golden/application.dets")
  |> should.equal("gleamunison_app_db_BCBAD5E6D46AB028")
}

pub fn store_log_table_name_golden_test() {
  store_log_name("/tmp/gleamunison-golden/log/content.dets")
  |> should.equal("gleamunison_store_log_9958D482EB48EFDE")
}

pub fn store_log_table_name_golden_unicode_path_test() {
  // The store_log site hashes unicode:characters_to_binary(Path); a UTF-8
  // path must keep producing the same atom the old site produced from the
  // equivalent charlist.
  store_log_name("/tmp/ünïcode-gölden.dets")
  |> should.equal("gleamunison_store_log_9B0BDE40C4B15C90")
}

pub fn storage_dets_table_name_golden_test() {
  storage_name("gleamunison_dets_/tmp/gleamunison-golden/chunks/main")
  |> should.equal(
    "gleamunison_aace1fc8d0b3bd0ca6e5a2c32bf06c05a7de81cb801512ca7c321147493b261a",
  )
}

pub fn storage_mnesia_table_name_golden_test() {
  storage_name("gleamunison_mnesia_refs")
  |> should.equal(
    "gleamunison_a90369cf6ad943cfe0aeab58862e423820c6b3240c490db4f4fb4a5c0aba723c",
  )
}
