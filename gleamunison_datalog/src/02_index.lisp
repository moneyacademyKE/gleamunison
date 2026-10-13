;; ─────────────────────────────────────────────────────────────────────────────
;; 02_index.lisp — EAVT and AVET index operations
;; Requires: 01_core.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; ── EAVT helpers ─────────────────────────────────────────────────────────────
;; eavt : {entity-id → {attr → [value ...]}}

(define eavt-entity-map
  (lam eavt (lam e
    (dict-safe-get eavt e (dict-new)))))

(define eavt-attr-vals
  (lam eavt (lam e (lam a
    (let em (eavt-entity-map eavt e)
      (dict-safe-get em a (list)))))))

(define eavt-insert
  (lam eavt (lam e (lam a (lam v
    (let em (eavt-entity-map eavt e)
      (let existing (dict-safe-get em a (list))
        (dict-set eavt e (dict-set em a (cons v existing))))))))))

(define eavt-remove-val
  (lam eavt (lam e (lam a (lam v
    (let em (eavt-entity-map eavt e)
      (let existing (dict-safe-get em a (list))
        (let filtered (list-filter (lam x (not (eq? x v))) existing)
          (dict-set eavt e (dict-set em a filtered))))))))))

(define eavt-remove-attr
  (lam eavt (lam e (lam a
    (let em (eavt-entity-map eavt e)
      (dict-set eavt e (dict-set em a (list))))))))

(define eavt-entity-pairs
  (lam eavt (lam e
    (eavt-entity-map eavt e))))

;; ── AVET helpers ─────────────────────────────────────────────────────────────
;; avet : {a → {v → [e ...]}} — a value may be claimed by many entities.

(define avet-lookup
  (lam avet (lam a (lam v
    (let attr-map (dict-safe-get avet a (dict-new))
      (dict-safe-get attr-map v (list)))))))

(define avet-insert
  (lam avet (lam a (lam v (lam e
    (let attr-map (dict-safe-get avet a (dict-new))
      (let existing (dict-safe-get attr-map v (list))
        (if (eq? (list-member? e existing) 1)
          (dict-set avet a (dict-set attr-map v existing))
          (dict-set avet a (dict-set attr-map v (cons e existing)))))))))))

(define avet-remove
  (lam avet (lam a (lam v (lam e
    (let attr-map (dict-safe-get avet a (dict-new))
      (let existing (dict-safe-get attr-map v (list))
        (dict-set avet a
          (dict-set attr-map v
            (list-filter (lam x (not (eq? x e))) existing))))))))))

(define db-entity-attrs
  (lam db (lam e
    (eavt-entity-map (db-eavt db) e))))

