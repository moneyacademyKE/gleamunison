;; ─────────────────────────────────────────────────────────────────────────────
;; 06_aggregate.lisp — Aggregate functions over query results
;; Requires: 05_query.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; Extract a variable's value from a binding set
(define binding-val
  (lam b (lam var-name
    (bindings-get b var-name))))

;; ── count ────────────────────────────────────────────────────────────────────
(define db-count
  (lam db (lam clauses (lam var-name
    (list-length (db-query db clauses))))))

;; ── collect ──────────────────────────────────────────────────────────────────
(define db-collect
  (lam db (lam clauses (lam var-name
    (list-map
      (lam b (binding-val b var-name))
      (db-query db clauses))))))

;; ── sum ───────────────────────────────────────────────────────────────────────
(define db-sum
  (lam db (lam clauses (lam var-name
    (list-fold
      (lam acc (lam b
        (let v (binding-val b var-name)
          (if (eq? v 0) acc (add acc v)))))
      0
      (db-query db clauses))))))

;; ── min ───────────────────────────────────────────────────────────────────────
(define db-min
  (lam db (lam clauses (lam var-name
    (let results (db-query db clauses)
      (list-fold
        (lam acc (lam b
          (let v (binding-val b var-name)
            (if (eq? acc 0) v
              (if (lt? v acc) v acc)))))
        0
        results))))))

;; ── max ───────────────────────────────────────────────────────────────────────
(define db-max
  (lam db (lam clauses (lam var-name
    (let results (db-query db clauses)
      (list-fold
        (lam acc (lam b
          (let v (binding-val b var-name)
            (if (eq? acc 0) v
              (if (gt? v acc) v acc)))))
        0
        results))))))

;; ── avg ───────────────────────────────────────────────────────────────────────
(define db-avg
  (lam db (lam clauses (lam var-name
    (let results (db-query db clauses)
      (let n (list-length results)
        (if (eq? n 0) 0
          (div (db-sum db clauses var-name) n))))))))

;; ── count-distinct ────────────────────────────────────────────────────────────
(define db-count-distinct
  (lam db (lam clauses (lam var-name
    (let vals (db-collect db clauses var-name)
      (list-length
        (list-fold
          (lam acc (lam v
            (if (list-member? v acc) acc (cons v acc))))
          (list)
          vals)))))))

