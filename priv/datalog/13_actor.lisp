;; ─────────────────────────────────────────────────────────────────────────────
;; 13_actor.lisp — Mutable DB Transactor process
;; Requires: 01_core.lisp, 03_transact.lisp, 05_query.lisp, 07_pull.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; The transactor message loop
(define db-actor-loop
  (lam db
    (let msg (recv)
      (let type (fst msg)
        (let payload (snd msg)
          (let reply-to (fst payload)
            (if (eq? type "transact")
              (let facts (snd payload)
                (let result (db-assert-many db facts)
                  (let _ (send reply-to (pair "ok" (db-tx result)))
                    (db-actor-loop result))))
              (if (eq? type "query")
                (let clauses (snd payload)
                  (let result (db-query db clauses)
                    (let _ (send reply-to (pair "ok" result))
                      (db-actor-loop db))))
                (if (eq? type "pull")
                  (let e (fst (snd payload))
                    (let pattern (snd (snd payload))
                      (let result (db-pull db e pattern)
                        (let _ (send reply-to (pair "ok" result))
                          (db-actor-loop db)))))
                  (db-actor-loop db))))))))))

;; ── db-spawn ─────────────────────────────────────────────────────────────────
;; Spawns a new database actor with an empty DB, returns its Process ID
(define db-spawn
  (lam dummy
    (spawn (lam dummy (db-actor-loop db-empty)))))

;; ── Client APIs ──────────────────────────────────────────────────────────────

(define db-client-transact
  (lam actor-pid (lam facts
    (let me (self)
      (let _ (send actor-pid (pair "transact" (pair me facts)))
        (let res (recv)
          (if (eq? (fst res) "ok")
            (snd res)
            0)))))))

(define db-client-query
  (lam actor-pid (lam clauses
    (let me (self)
      (let _ (send actor-pid (pair "query" (pair me clauses)))
        (let res (recv)
          (if (eq? (fst res) "ok")
            (snd res)
            (list))))))))

(define db-client-pull
  (lam actor-pid (lam entity (lam pattern
    (let me (self)
      (let _ (send actor-pid (pair "pull" (pair me (pair entity pattern))))
        (let res (recv)
          (if (eq? (fst res) "ok")
            (snd res)
            (dict-new)))))))))

