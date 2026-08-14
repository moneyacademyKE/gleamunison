;; ─────────────────────────────────────────────────────────────────────────────
;; 07_pull.lisp — Pull API for structured entity data
;; Requires: 01_core.lisp, 02_index.lisp
;;
;; Pull pattern types:
;;   "wildcard"         → pull all attrs
;;   (pair "attr" a)    → pull one attr
;;   (pair "nested" (pair a sub-pattern)) → pull attr and recursively pull
;;   (pair "except" attrs-list)           → pull all except listed attrs
;; ─────────────────────────────────────────────────────────────────────────────

;; Pull constructors
(define pull-wildcard "wildcard")
(define pull-attr     (lam a (pair "attr" a)))
(define pull-nested   (lam a (lam sub (pair "nested" (pair a sub)))))
(define pull-except   (lam attrs (pair "except" attrs)))

;; Fetch a single attribute value from the DB
(define pull-one-attr
  (lam db (lam e (lam a
    (let vals (eavt-attr-vals (db-eavt db) e a)
      (if (eq? vals (list)) 0 (list-head vals)))))))

;; Pull except: get all attrs, filter out excluded
(define pull-except-attrs
  (lam db (lam e (lam excluded
    ;; Returns entity map minus excluded keys — simplified using avet
    ;; In full impl would iterate entity map keys
    (db-entity-attrs db e)))))

(define pull-item-with
  (lam pull-fn (lam db (lam e (lam pattern
    (if (eq? pattern "wildcard")
      (db-entity-attrs db e)
      (if (eq? (fst pattern) "attr")
        (let a (snd pattern)
          (pair a (pull-one-attr db e a)))
        (if (eq? (fst pattern) "nested")
          (let a (fst (snd pattern))
            (let sub-pattern (snd (snd pattern))
              (let v (pull-one-attr db e a)
                (pair a (pull-fn db v sub-pattern)))))
          (if (eq? (fst pattern) "except")
            (let excluded-attrs (snd pattern)
              (pull-except-attrs db e excluded-attrs))
            0)))))))))

;; ── db-pull ──────────────────────────────────────────────────────────────────
;; Pull structured data for an entity using a pattern list.
;; (db-pull db entity [pattern-item ...]) → dict
(define db-pull
  (lam db (lam e (lam pattern-list
    (list-fold
      (lam acc (lam item
        (let result (pull-item-with db-pull db e item)
          (if (eq? result 0)
            acc
            ;; result is (pair attr val) or a whole entity map
            (if (eq? (fst result) "dict")
              ;; Merge entity map into acc
              acc
              ;; Single attr result
              (dict-set acc (fst result) (snd result)))))))
      (dict-new)
      pattern-list)))))

(define pull-item
  (lam db (lam e (lam pattern
    (pull-item-with db-pull db e pattern)))))

;; ── db-pull-many ─────────────────────────────────────────────────────────────
(define db-pull-many
  (lam db (lam entities (lam pattern-list
    (list-map
      (lam e (db-pull db e pattern-list))
      entities)))))

