;; ─────────────────────────────────────────────────────────────────────────────
;; test_query.lisp — Query engine and aggregate tests
;; Requires: 05_query.lisp, 06_aggregate.lisp
;; ─────────────────────────────────────────────────────────────────────────────

(define test-unify
  (lam dummy
    (let b1 (unify-part (q-var "?x") 10 bindings-empty)
      (let b2 (unify-part (q-var "?x") 20 (snd b1))
        (let b3 (unify-part (q-var "?x") 10 (snd b1))
          (and
            (fst b1)
            (and
              (not (fst b2))
              (fst b3))))))))

(define test-simple-query
  (lam dummy
    (let db (db-assert db-empty 1 "name" "Alice")
      (let db (db-assert db 1 "age" 30)
        (let db (db-assert db 2 "name" "Bob")
          (let db (db-assert db 2 "age" 25)
            (let clauses
              (list
                (pair (q-var "?e") (pair "name" (q-var "?name")))
                (pair (q-var "?e") (pair "age" (q-val 30))))
              (let results (db-query db clauses)
                (let n (list-length results)
                  (let match-name (bindings-get (list-head results) "?name")
                    (and (eq? n 1) (eq? match-name "Alice"))))))))))))

(define test-aggregates
  (lam dummy
    (let db (db-assert db-empty 1 "val" 10)
      (let db (db-assert db 2 "val" 20)
        (let db (db-assert db 3 "val" 30)
          (let clauses (list (pair (q-var "?e") (pair "val" (q-var "?v"))))
            (let cnt (db-count db clauses "?v")
              (let sm (db-sum db clauses "?v")
                (let mn (db-min db clauses "?v")
                  (let mx (db-max db clauses "?v")
                    (let av (db-avg db clauses "?v")
                      (and (eq? cnt 3)
                        (and (eq? sm 60)
                          (and (eq? mn 10)
                            (and (eq? mx 30)
                              (eq? av 20))))))))))))))))

(define run-query-tests
  (lam dummy
    (list
      (assert-eq true (test-unify 0) "test-unify")
      (assert-eq true (test-simple-query 0) "test-simple-query")
      (assert-eq true (test-aggregates 0) "test-aggregates"))))

