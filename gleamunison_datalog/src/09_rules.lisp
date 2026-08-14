;; ─────────────────────────────────────────────────────────────────────────────
;; 09_rules.lisp — Datalog rules and fixed-point recursive solver
;; Requires: 05_query.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; Rule constructor: (pair head-clause body-clauses)
;; head-clause: (pair rule-name (pair var1 var2 ...))
;; body-clauses: list of query clauses
(define rule-make
  (lam head (lam body
    (pair head body))))

(define rule-head (lam r (fst r)))
(define rule-body (lam r (snd r)))
(define rule-name (lam r (fst (rule-head r))))
(define rule-args (lam r (snd (rule-head r))))

;; Apply a rule: run query body, project onto head variables to produce derived facts
(define rule-apply
  (lam db (lam rule (lam bindings
    (let body-results (db-query db (rule-body rule))
      ;; For each result binding, construct a derived fact matching the rule's head
      (list-map
        (lam b
          ;; Resolve head variables
          (let args (rule-args rule)
            (let resolved-args
              (list-map
                (lam arg
                  (if (q-var? arg)
                    (let v (bindings-get b (q-var-name arg))
                      (if (eq? v 0) arg (q-val v)))
                    arg))
                args)
              (pair (rule-name rule) resolved-args))))
        body-results))))))

;; ── Fixed-point recursive evaluation ─────────────────────────────────────────
;; Given a list of rules, evaluate recursively until no new derived facts are found.
;; We add derived facts to a virtual db state extension.

(define db-with-derived-facts
  (lam db (lam derived-facts
    ;; derived-facts: list of (pair rule-name (pair arg1 arg2 ...))
    ;; For simplicity, we just assert them as facts in the virtual DB
    (list-fold
      (lam acc-db (lam fact
        (let r-name (fst fact)
          (let args (snd fact)
            ;; We assert rule-derived facts under the entity of the first arg,
            ;; attribute of rule-name, and value of the remaining args
            (let e (q-val-value (fst args))
              (let v (q-val-value (fst (snd args)))
                (db-assert acc-db e r-name v)))))))
      db
      derived-facts))))

(define rule-solve-recursive
  (lam db (lam rules (lam max-iterations
    (let step
      (lam self (lam current-db (lam iter (lam prev-fact-count
        (if (eq? iter 0)
          current-db
          ;; Apply all rules to current db
          (let derived (list-flatten (list-map (lam r (rule-apply current-db r bindings-empty)) rules))
            ;; Filter to keep unique derived facts
            (let unique-derived
              (list-fold
                (lam acc (lam f (if (list-member? f acc) acc (pair f acc))))
                (list)
                derived)
              (let new-db (db-with-derived-facts db unique-derived)
                ;; Count new facts in eavt
                (let new-fact-count (list-length unique-derived)
                  (if (eq? new-fact-count prev-fact-count)
                    current-db
                    (self self new-db (sub iter 1) new-fact-count)))))))))))
      (step step db max-iterations 0))))))

