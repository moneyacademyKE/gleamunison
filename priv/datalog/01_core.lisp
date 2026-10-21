;; ─────────────────────────────────────────────────────────────────────────────
;; 01_core.lisp — Datom model and DB state structure
;; GleamUnison Datalog DB — native S-expression implementation
;; Every definition is content-addressed by SHA256 in the gleamunison codebase.
;; ─────────────────────────────────────────────────────────────────────────────

(define true 1)
(define false 0)
(define not (lam x (if (eq? x 0) 1 0)))
(define and (lam a (lam b (if (eq? a 0) 0 (if (eq? b 0) 0 1)))))
(define or  (lam a (lam b (if (eq? a 1) 1 (if (eq? b 1) 1 0)))))
(define lte? (lam a (lam b (if (lt? a b) 1 (if (eq? a b) 1 0)))))
(define gte? (lam a (lam b (if (gt? a b) 1 (if (eq? a b) 1 0)))))
(define null (dict-get (dict-new) "__missing__"))
(define dict-safe-get
  (lam d (lam k (lam default
    (if (or (eq? d null) (eq? d 0))
      default
      (let res (dict-get d k)
        (if (eq? res null) default res)))))))
(define cons (lam x (lam xs (list-append (list x) xs))))
(define list-head
  (lam lst
    (snd
      (list-fold
        (lam acc (lam x
          (if (fst acc)
            acc
            (pair true x))))
        (pair false 0)
        lst))))
(define list-tail
  (lam lst
    (snd
      (list-fold
        (lam acc (lam x
          (if (fst acc)
            (pair true (list-append (snd acc) (list x)))
            (pair true (list)))))
        (pair false (list))
        lst))))
(define list-member?
  (lam item (lam lst
    (list-fold
      (lam found (lam x
        (if (eq? found 1) 1 (if (eq? x item) 1 0))))
      0
      lst))))

;; A datom is a 4-tuple: (e, a, v, tx)
;; Encoded as nested pairs: (pair e (pair a (pair v tx)))

(define datom-make
  (lam e (lam a (lam v (lam tx
    (pair e (pair a (pair v tx))))))))

(define datom-e   (lam d (fst d)))
(define datom-a   (lam d (fst (snd d))))
(define datom-v   (lam d (fst (snd (snd d)))))
(define datom-tx  (lam d (snd (snd (snd d)))))

;; DB state: (pair eavt (pair avet (pair log tx)))
;; eavt : {e → {a → [v ...]}}     — primary index
;; avet : {a → {v → [e ...]}}       — lookup index (values are NOT unique:
;; many entities may share a value, e.g. def/kind = "term")
;; log  : [[datom ...] ...]        — append-only tx history
;; tx   : Int                      — current transaction number

(define db-eavt   (lam db (fst db)))
(define db-avet   (lam db (fst (snd db))))
(define db-log    (lam db (fst (snd (snd db)))))
(define db-tx     (lam db (snd (snd (snd db)))))

;; Empty database
(define db-empty
  (pair (dict-new) (pair (dict-new) (pair (list) 0))))

;; Construct a new DB from components
(define db-make
  (lam eavt (lam avet (lam log (lam tx
    (pair eavt (pair avet (pair log tx))))))))

;; Bump tx counter
(define db-next-tx
  (lam db
    (db-make (db-eavt db) (db-avet db) (db-log db) (add (db-tx db) 1))))

;; Check if db is empty
(define db-empty?
  (lam db
    (eq? (db-tx db) 0)))
