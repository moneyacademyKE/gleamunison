;; ─────────────────────────────────────────────────────────────────────────────
;; 11_vector.lisp — Vector similarity and k-Nearest-Neighbor
;; Requires: 01_core.lisp, 05_query.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; Helper to zip two lists together
(define list-zip
  (lam l1 (lam l2
    (let loop
      (lam self (lam xs (lam ys (lam acc
        (if (or (eq? xs (list)) (eq? ys (list)))
          acc
          (self self (list-tail xs) (list-tail ys) (cons (pair (list-head xs) (list-head ys)) acc)))))))
      (list-reverse (loop loop l1 l2 (list)))))))

;; Helper to take first N elements of a list
(define list-take
  (lam n (lam xs
    (let loop
      (lam self (lam count (lam list-val (lam acc
        (if (or (eq? count 0) (eq? list-val (list)))
          acc
          (self self (sub count 1) (list-tail list-val) (cons (list-head list-val) acc)))))))
      (list-reverse (loop loop n xs (list)))))))

;; ── Dot Product ──────────────────────────────────────────────────────────────
;; (vector-dot-product v1 v2) → Int (using integer scaling for precision)
(define vector-dot-product
  (lam v1 (lam v2
    (let pairs (list-zip v1 v2)
      (list-fold
        (lam acc (lam p
          (add acc (mul (fst p) (snd p)))))
        0
        pairs)))))

;; ── Magnitude squared ────────────────────────────────────────────────────────
(define vector-mag-sq
  (lam v
    (vector-dot-product v v)))

;; ── Cosine Similarity ────────────────────────────────────────────────────────
;; Returns similarity score as Int (scaled by 10000, i.e., 1.0 = 10000)
;; Approximate square root via integer math (Newton-Raphson method)
(define int-sqrt
  (lam n
    (let solve
      (lam self (lam x
        (let next (div (add x (div n x)) 2)
          (if (gte? next x)
            x
            (self self next)))))
      (if (lt? n 2) n (solve solve n)))))

(define vector-cosine-similarity
  (lam v1 (lam v2
    (let dot (vector-dot-product v1 v2)
      (let mag1 (int-sqrt (vector-mag-sq v1))
        (let mag2 (int-sqrt (vector-mag-sq v2))
          (let denom (mul mag1 mag2)
            (if (eq? denom 0)
              0
              (div (mul dot 10000) denom)))))))))

;; ── k-Nearest-Neighbor (k-NN) ────────────────────────────────────────────────
;; Finds the top k entities that have vector attribute `vec-attr` closest to `query-vec`
(define vector-knn
  (lam db (lam query-vec (lam vec-attr (lam k
    (let entities (db-find db vec-attr 0)
      (let scored-entities
        (list-map
          (lam e
            (let v (list-head (eavt-attr-vals (db-eavt db) e vec-attr))
              (let score (vector-cosine-similarity query-vec v)
                (pair score e))))
          entities)
        (let sorted (list-sort (lam p1 (lam p2 (gt? (fst p1) (fst p2)))) scored-entities)
          (list-take k sorted)))))))))


