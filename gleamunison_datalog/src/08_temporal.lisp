;; ─────────────────────────────────────────────────────────────────────────────
;; 08_temporal.lisp — History, as-of, since, diff temporal queries
;; Requires: 01_core.lisp, 03_transact.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; ── db-history ───────────────────────────────────────────────────────────────
;; Get all transaction states/datoms in chronological order for (e, a)
(define db-history
  (lam db (lam e (lam a
    (let transactions (list-reverse (db-log db))
      (list-flatten
        (list-map
          (lam tx-datoms
            (list-filter
              (lam d
                (and (eq? (datom-e d) e) (eq? (datom-a d) a)))
              tx-datoms))
          transactions)))))))

;; ── db-as-of ─────────────────────────────────────────────────────────────────
;; Returns a snapshot of the DB state as of a given transaction number/time tx-val.
;; Rebuilds EAVT and AVET indexes by replaying the log up to tx-val.
(define db-as-of
  (lam db (lam tx-val
    (let transactions (list-reverse (db-log db))
      (list-fold
        (lam acc-db (lam tx-datoms
          (let first-d (list-head tx-datoms)
            (if (lte? (datom-tx first-d) tx-val)
              (list-fold
                (lam sub-db (lam d
                  (let e (datom-e d)
                    (let a (datom-a d)
                      (let v (datom-v d)
                        (if (eq? a "retract-all")
                          (db-retract-attr sub-db e a)
                          (if (eq? a "retract-entity")
                            (db-retract-entity sub-db e)
                            (db-assert sub-db e a v))))))))
                acc-db
                tx-datoms)
              acc-db))))
        db-empty
        transactions)))))

;; ── db-since ─────────────────────────────────────────────────────────────────
;; Get all datoms asserted/retracted since a given transaction number tx-val.
(define db-since
  (lam db (lam tx-val
    (let transactions (list-reverse (db-log db))
      (list-flatten
        (list-map
          (lam tx-datoms
            (list-filter
              (lam d (gt? (datom-tx d) tx-val))
              tx-datoms))
          transactions))))))

;; ── db-diff ──────────────────────────────────────────────────────────────────
;; Computes difference of datoms between two database states (tx1 to tx2).
(define db-diff
  (lam db (lam tx1 (lam tx2
    (let transactions (list-reverse (db-log db))
      (list-flatten
        (list-map
          (lam tx-datoms
            (list-filter
              (lam d
                (and (gt? (datom-tx d) tx1) (lte? (datom-tx d) tx2)))
              tx-datoms))
          transactions)))))))

