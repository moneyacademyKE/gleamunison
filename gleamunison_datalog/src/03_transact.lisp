;; ─────────────────────────────────────────────────────────────────────────────
;; 03_transact.lisp — Assert, retract, CAS operations
;; Requires: 01_core.lisp, 02_index.lisp
;; Returns a NEW immutable DB — pure functional, like Datomic.
;; ─────────────────────────────────────────────────────────────────────────────

;; Internal: build datom and append to log
(define db-with-datom
  (lam db (lam e (lam a (lam v (lam added
    (let tx (add (db-tx db) 1)
      (let d (datom-make e a v tx)
        (let new-log (cons (list d) (db-log db))
          (pair (db-eavt db)
            (pair (db-avet db)
              (pair new-log tx))))))))))))

;; ── db-assert ────────────────────────────────────────────────────────────────
;; Assert a fact: (db-assert db entity attr value)
;; Returns new db with the fact added to EAVT, AVET, and log.
(define db-assert
  (lam db (lam e (lam a (lam v
    (let tx (add (db-tx db) 1)
      (let d (datom-make e a v tx)
        (let new-eavt (eavt-insert (db-eavt db) e a v)
          (let new-avet (avet-insert (db-avet db) a v e)
            (let new-log (cons (list d) (db-log db))
              (db-make new-eavt new-avet new-log tx)))))))))))

;; ── db-assert-many ───────────────────────────────────────────────────────────
;; Assert a list of [e a v] triples in one transaction.
;; Each triple is a pair: (pair e (pair a v))
(define db-assert-many
  (lam db (lam triples
    (list-fold
      (lam acc (lam triple
        (let e (fst triple)
          (let a (fst (snd triple))
            (let v (snd (snd triple))
              (db-assert acc e a v))))))
      db
      triples))))

;; ── db-retract ───────────────────────────────────────────────────────────────
;; Retract a specific fact: (db-retract db entity attr value)
(define db-retract
  (lam db (lam e (lam a (lam v
    (let tx (add (db-tx db) 1)
      (let d (datom-make e a (pair "retract" v) tx)
        (let new-eavt (eavt-remove-val (db-eavt db) e a v)
          (let new-avet (avet-remove (db-avet db) a v)
            (let new-log (cons (list d) (db-log db))
              (db-make new-eavt new-avet new-log tx)))))))))))

;; ── db-retract-attr ──────────────────────────────────────────────────────────
;; Retract all values for an entity-attribute pair.
(define db-retract-attr
  (lam db (lam e (lam a
    (let tx (add (db-tx db) 1)
      (let d (datom-make e a "retract-all" tx)
        (let new-eavt (eavt-remove-attr (db-eavt db) e a)
          (let new-log (cons (list d) (db-log db))
            (db-make new-eavt (db-avet db) new-log tx)))))))))

;; ── db-retract-entity ────────────────────────────────────────────────────────
;; Retract ALL facts for an entity.
(define db-retract-entity
  (lam db (lam e
    (let tx (add (db-tx db) 1)
      (let d (datom-make e "retract-entity" 0 tx)
        (let new-eavt (dict-set (db-eavt db) e (dict-new))
          (let new-log (cons (list d) (db-log db))
            (db-make new-eavt (db-avet db) new-log tx))))))))

;; ── db-cas ───────────────────────────────────────────────────────────────────
;; Compare-and-swap: only asserts new-v if current value is old-v.
;; Returns (pair success? new-db)
(define db-cas
  (lam db (lam e (lam a (lam old-v (lam new-v
    (let current-vals (eavt-attr-vals (db-eavt db) e a)
      (if (list-member? old-v current-vals)
        (let db2 (db-retract db e a old-v)
          (pair true (db-assert db2 e a new-v)))
        (pair false db)))))))))


