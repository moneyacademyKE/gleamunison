;; ─────────────────────────────────────────────────────────────────────────────
;; test_temporal.lisp — Temporal indexing and query tests
;; Requires: 08_temporal.lisp
;; ─────────────────────────────────────────────────────────────────────────────

(define test-history
  (lam dummy
    (let db (db-assert db-empty 1 "status" "draft")
      (let db (db-assert db 1 "status" "published")
        (let h (db-history db 1 "status")
          (let n (list-length h)
            (let first-val (datom-v (list-head h))
              (let second-val (datom-v (list-head (list-tail h)))
                (and (eq? n 2)
                  (and (eq? first-val "published")
                    (eq? second-val "draft")))))))))))

(define test-as-of
  (lam dummy
    (let db (db-assert db-empty 1 "version" 1)
      (let t1 (db-tx db)
        (let db (db-assert db 1 "version" 2)
          (let t2 (db-tx db)
            (let db (db-assert db 1 "version" 3)
              (let db-t1 (db-as-of db t1)
                (let db-t2 (db-as-of db t2)
                  (let v1 (list-head (eavt-attr-vals (db-eavt db-t1) 1 "version"))
                    (let v2 (list-head (eavt-attr-vals (db-eavt db-t2) 1 "version"))
                      (and (eq? v1 1) (eq? v2 2)))))))))))))

(define test-since-diff
  (lam dummy
    (let db (db-assert db-empty 1 "val" 100)
      (let t1 (db-tx db)
        (let db (db-assert db 1 "val" 200)
          (let t2 (db-tx db)
            (let db (db-assert db 1 "val" 300)
              (let s (db-since db t1)
                (let d (db-diff db t1 t2)
                  (and (eq? (list-length s) 2)
                    (eq? (list-length d) 1)))))))))))

(define run-temporal-tests
  (lam dummy
    (list
      (assert-eq true (test-history 0) "test-history")
      (assert-eq true (test-as-of 0) "test-as-of")
      (assert-eq true (test-since-diff 0) "test-since-diff"))))

