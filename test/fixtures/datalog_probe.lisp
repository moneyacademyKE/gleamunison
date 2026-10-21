;; Deterministic probe for the shipped datalog engine (bk-389b).
;; Run: gleamunison_escript datalog test/fixtures/datalog_probe.lisp
(eavt-attr-vals (db-eavt (db-assert db-empty 1 "age" 30)) 1 "age")
