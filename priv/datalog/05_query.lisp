;; ─────────────────────────────────────────────────────────────────────────────
;; 05_query.lisp — Datalog query engine
;; Requires: 01_core.lisp, 02_index.lisp
;;
;; Query model:
;;   A query is a list of clauses. Each clause is a triple pattern.
;;   A triple pattern: (pair e-pat (pair a v-pat))
;;   A pattern part is either:
;;     (pair "var" name)   — a logic variable
;;     (pair "val" value)  — a concrete value
;;
;; Result: a list of binding dicts {var-name → value}
;; ─────────────────────────────────────────────────────────────────────────────

;; ── Pattern constructors ─────────────────────────────────────────────────────
(define q-var (lam name (pair "var" name)))
(define q-val (lam v    (pair "val" v)))

(define q-var? (lam p (eq? (fst p) "var")))
(define q-val? (lam p (eq? (fst p) "val")))
(define q-var-name (lam p (snd p)))
(define q-val-value (lam p (snd p)))

;; ── Bindings ─────────────────────────────────────────────────────────────────
(define bindings-empty (dict-new))

(define bindings-get
  (lam b (lam name (dict-safe-get b name 0))))

(define bindings-set
  (lam b (lam name (lam val (dict-set b name val)))))

;; Resolve a pattern part against current bindings
(define resolve-part
  (lam part (lam bindings
    (if (q-var? part)
      (let bound (bindings-get bindings (q-var-name part))
        (if (eq? bound 0) (pair false 0) (pair true bound)))
      (pair true (q-val-value part))))))

;; Attempt to unify a part with a concrete value — returns new bindings or false
(define unify-part
  (lam part (lam value (lam bindings
    (if (q-var? part)
      (let name (q-var-name part)
        (let existing (bindings-get bindings name)
          (if (eq? existing 0)
            (pair true (bindings-set bindings name value))
            (if (eq? existing value)
              (pair true bindings)
              (pair false bindings)))))
      (if (eq? (q-val-value part) value)
        (pair true bindings)
        (pair false bindings)))))))

;; ── list-filter-map helper ───────────────────────────────────────────────────
;; Apply f to each element; keep only (pair true val) results, collect val
(define list-filter-map
  (lam f (lam lst
    (list-fold
      (lam acc (lam x
        (let result (f x)
          (if (fst result)
            (cons (snd result) acc)
            acc))))
      (list)
      lst))))

;; Fold over an AVET attribute map, collecting matching bindings.
;; v bound  → point lookup, then unify the entity.
;; v unbound → iterate every value in the attribute index via dict-keys,
;;             unifying both the value and the entity.
(define db-avet-fold
  (lam attr-map (lam e-pat (lam v-pat (lam bindings
    (let v-resolved (resolve-part v-pat bindings)
      (if (fst v-resolved)
        ;; v is bound — unify e-pat against every entity recorded for v
        (let v (snd v-resolved)
          (let es (dict-safe-get attr-map v (list))
            (list-filter-map
              (lam e
                (let u-result (unify-part e-pat e bindings)
                  (if (fst u-result)
                    (pair true (snd u-result))
                    (pair false bindings))))
              es)))
        ;; v unbound — scan every value in this attribute's index via
        ;; dict-keys, then every entity recorded under each value
        (list-flatten
          (list-map
            (lam v
              (let es (dict-safe-get attr-map v (list))
                (list-filter-map
                  (lam e
                    (let u1 (unify-part v-pat v bindings)
                      (if (fst u1)
                        (let u2 (unify-part e-pat e (snd u1))
                          (if (fst u2)
                            (pair true (snd u2))
                            (pair false bindings)))
                        (pair false bindings))))
                  es)))
            (dict-keys attr-map))))))))))

;; Scan all entities for those matching (attr, v-pat)
(define db-scan-attr
  (lam db (lam attr (lam e-pat (lam v-pat (lam bindings
    (let attr-map (dict-safe-get (db-avet db) attr (dict-new))
      (db-avet-fold attr-map e-pat v-pat bindings))))))))

;; ── Triple clause solving ────────────────────────────────────────────────────
;; A clause is (pair e-pat (pair attr v-pat))
;; Returns list of new binding environments
(define solve-clause
  (lam db (lam clause (lam bindings
    (let e-pat (fst clause)
      (let attr  (fst (snd clause))
        (let v-pat (snd (snd clause))
          ;; Resolve entity part
          (let e-resolved (resolve-part e-pat bindings)
            (if (fst e-resolved)
              ;; Entity is bound — look up its attributes directly
              (let e (snd e-resolved)
                (let vals (eavt-attr-vals (db-eavt db) e attr)
                  (list-filter-map
                    (lam v
                      (let u-result (unify-part v-pat v bindings)
                        (if (fst u-result)
                          (pair true (snd u-result))
                          (pair false bindings))))
                    vals)))
              ;; Entity unbound — scan all entities with this attribute
              (let aevt (db-avet db)
                ;; We collect all entities from the eavt that have this attr
                (db-scan-attr db attr e-pat v-pat bindings)))))))))))

;; ── Full query execution ──────────────────────────────────────────────────────
;; (db-query db clauses) → list of binding dicts
(define db-query
  (lam db (lam clauses
    (list-fold
      (lam binding-sets (lam clause
        (list-flatten
          (list-map
            (lam bindings (solve-clause db clause bindings))
            binding-sets))))
      (list bindings-empty)
      clauses))))

;; ── Convenience: find by attribute = value ───────────────────────────────────
(define db-find
  (lam db (lam attr (lam value
    (let clause (pair (q-var "?e") (pair attr (q-val value)))
      (let results (db-query db (list clause))
        (list-map
          (lam b (bindings-get b "?e"))
          results)))))))


