;; ─────────────────────────────────────────────────────────────────────────────
;; 04_schema.lisp — Schema definitions and constraint validation
;; Requires: 01_core.lisp, 02_index.lisp, 03_transact.lisp
;; ─────────────────────────────────────────────────────────────────────────────

(define schema-empty-cfg
  (dict-new))

(define schema-cfg
  (lam unique (lam cardinality (lam component
    (dict-set
      (dict-set
        (dict-set (dict-new) "unique" unique)
        "cardinality" cardinality)
      "component" component)))))

(define schema-unique?     (lam cfg (dict-safe-get cfg "unique" 0)))
(define schema-cardinality (lam cfg (dict-safe-get cfg "cardinality" "one")))
(define schema-component?  (lam cfg (dict-safe-get cfg "component" 0)))

;; The schema registry is itself a dict stored in the DB state
;; We use a reserved top-level key "db/schema" in the eavt under entity 0
(define schema-get
  (lam db (lam attr
    (let schema-eid 0
      (let em (eavt-entity-map (db-eavt db) schema-eid)
        (dict-safe-get em attr schema-empty-cfg))))))

(define schema-put
  (lam db (lam attr (lam cfg
    (let schema-eid 0
      (let em (eavt-entity-map (db-eavt db) schema-eid)
        (let new-em (dict-set em attr cfg)
          (let new-eavt (dict-set (db-eavt db) schema-eid new-em)
            (db-make new-eavt (db-avet db) (db-log db) (db-tx db))))))))))

;; Register an attribute with its config
(define db-register-attr
  (lam db (lam attr (lam cfg
    (schema-put db attr cfg)))))

;; ── Constraint validation ────────────────────────────────────────────────────

;; Check uniqueness: is this (a,v) pair already claimed by a different entity?
(define check-unique
  (lam db (lam e (lam a (lam v
    (let cfg (schema-get db a)
      (if (schema-unique? cfg)
        (let existing (avet-lookup (db-avet db) a v)
          ;; existing is the list of entities currently claiming (a,v)
          (if (eq? existing (list))
            (pair true "")
            (if (and (eq? (list-length existing) 1)
                  (eq? (list-head existing) e))
              (pair true "")
              (pair false (string-concat "unique violation: " a)))))
        (pair true ""))))))))

;; Check cardinality: for :one, we must retract the old value first
(define check-cardinality-one
  (lam db (lam e (lam a (lam v
    (let cfg (schema-get db a)
      (if (eq? (schema-cardinality cfg) "one")
        (let current (eavt-attr-vals (db-eavt db) e a)
          (if (eq? current (list))
            (pair true db)
            (let old-v (list-head current)
              (pair true (db-retract db e a old-v)))))
        (pair true db))))))))

;; Assert with constraint checking
(define db-assert-checked
  (lam db (lam e (lam a (lam v
    (let u-check (check-unique db e a v)
      (if (not (fst u-check))
        (pair false (snd u-check))
        (let c-result (check-cardinality-one db e a v)
          (let db2 (snd c-result)
            (pair true (db-assert db2 e a v)))))))))))
