;; ─────────────────────────────────────────────────────────────────────────────
;; test_core.lisp — Core functionality tests
;; ─────────────────────────────────────────────────────────────────────────────

(define assert-eq
  (lam expected (lam actual (lam test-name
    (if (eq? expected actual)
      (pair true test-name)
      (pair false (string-concat "FAIL: " test-name)))))))

;; Test datom constructors
(define test-datom-creation
  (lam dummy
    (let d (datom-make 1 "name" "Alice" 42)
      (let e-ok (eq? (datom-e d) 1)
        (let a-ok (eq? (datom-a d) "name")
          (let v-ok (eq? (datom-v d) "Alice")
            (let tx-ok (eq? (datom-tx d) 42)
              (and e-ok (and a-ok (and v-ok tx-ok))))))))))

;; Test simple transaction assert/retract
(define test-basic-transact
  (lam dummy
    (let db (db-assert db-empty 1 "age" 30)
      (let age-val (list-head (eavt-attr-vals (db-eavt db) 1 "age"))
        (let db2 (db-retract db 1 "age" 30)
          (let retracted-vals (eavt-attr-vals (db-eavt db2) 1 "age")
            (and (eq? age-val 30) (eq? retracted-vals (list)))))))))

;; Test Compare-and-Swap (CAS)
(define test-cas
  (lam dummy
    (let db (db-assert db-empty 1 "status" "active")
      (let cas-result1 (db-cas db 1 "status" "inactive" "pending")
        (let cas-result2 (db-cas db 1 "status" "active" "pending")
          (let success1 (not (fst cas-result1))
            (let success2 (fst cas-result2)
              (let db-final (snd cas-result2)
                (let final-val (list-head (eavt-attr-vals (db-eavt db-final) 1 "status"))
                  (and success1 (and success2 (eq? final-val "pending"))))))))))))

;; Run all core tests
(define run-core-tests
  (lam dummy
    (list
      (assert-eq true (test-datom-creation 0) "test-datom-creation")
      (assert-eq true (test-basic-transact 0) "test-basic-transact")
      (assert-eq true (test-cas 0) "test-cas"))))
