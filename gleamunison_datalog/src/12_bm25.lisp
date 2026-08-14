;; ─────────────────────────────────────────────────────────────────────────────
;; 12_bm25.lisp — BM25 Full-text search index and ranking
;; Requires: 01_core.lisp, 02_index.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; ── Term frequency ───────────────────────────────────────────────────────────
;; Counts how many times `term` appears in `doc-words` (list of strings)
(define bm25-tf
  (lam term (lam doc-words
    (list-fold
      (lam acc (lam w (if (eq? w term) (add acc 1) acc)))
      0
      doc-words))))

;; ── Document Frequency (DF) ──────────────────────────────────────────────────
;; Counts how many documents contain `term`
(define bm25-df
  (lam term (lam docs-words-list
    (list-fold
      (lam acc (lam doc-words
        (if (gt? (bm25-tf term doc-words) 0)
          (add acc 1)
          acc)))
      0
      docs-words-list))))

;; ── Inverse Document Frequency (IDF) ─────────────────────────────────────────
;; Calculates IDF score scaled by 1000: log((N - n + 0.5) / (n + 0.5) + 1)
;; Using integer log approximation: log_approx(x) = ln(x) * 1000
(define idf-ln-approx
  (lam x
    ;; Extremely simple ln approximation for small values
    ;; ln(x) = (x - 1) - (x - 1)^2 / 2 + ...
    (if (lt? x 2)
      0
      (if (lt? x 5)
        1000
        (if (lt? x 10)
          2000
          3000)))))

(define bm25-idf
  (lam term (lam docs-words-list
    (let n (list-length docs-words-list)
      (let df (bm25-df term docs-words-list)
        ;; idf = ln((N - df + 0.5) / (df + 0.5) + 1)
        ;; Scaling integers by 10
        (let num (add (sub (mul n 10) (mul df 10)) 5)
          (let denom (add (mul df 10) 5)
            (let ratio (add (div (mul num 10) denom) 10)
              (idf-ln-approx (div ratio 10))))))))))

;; ── Document scoring ─────────────────────────────────────────────────────────
;; Score a single document (doc-words) against a single term
;; Score = idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (dl / avgdl)))
;; k1 = 1.5 (scaled to 15), b = 0.75 (scaled to 75)
(define bm25-score-term
  (lam term (lam doc-words (lam idf (lam avgdl
    (let tf (bm25-tf term doc-words)
      (if (eq? tf 0)
        0
        (let dl (list-length doc-words)
          ;; k1 = 15, b = 75, avgdl scaled by 100
          (let k1 15
            (let b 75
              (let num (mul tf (add k1 10))
                ;; denom-part = 100 - b + b * dl / avgdl
                (let dl-avgdl (div (mul dl 100) avgdl)
                  (let b-dl-avgdl (div (mul b dl-avgdl) 100)
                    (let denom-part (add (sub 100 b) b-dl-avgdl)
                      (let denom (add (mul tf 10) (div (mul k1 denom-part) 10))
                        (div (mul idf num) denom))))))))))))))))

;; ── Rank documents ───────────────────────────────────────────────────────────
;; (bm25-rank db term text-attr) → list of (pair score entity)
(define bm25-rank
  (lam db (lam term (lam text-attr
    ;; Get all entities with this text attribute
    (let entities (db-find db text-attr 0)
      ;; For simplicity, we split text string by space — assuming words are separated by space
      ;; Actually we'll assume values are already lists of strings (words) in this native engine.
      (let docs
        (list-map
          (lam e
            (let words (list-head (eavt-attr-vals (db-eavt db) e text-attr))
              (pair e words)))
          entities)
        (let docs-words (list-map (lam p (snd p)) docs)
          (let idf (bm25-idf term docs-words)
            ;; Calculate average doc length
            (let total-len
              (list-fold (lam acc (lam words (add acc (list-length words)))) 0 docs-words)
              (let num-docs (list-length docs-words)
                (let avgdl (if (eq? num-docs 0) 1 (div total-len num-docs))
                  ;; Score each doc
                  (let scored
                    (list-map
                      (lam d
                        (let e (fst d)
                          (let words (snd d)
                            (let score (bm25-score-term term words idf avgdl)
                              (pair score e)))))
                      docs)
                    (list-sort (lam p1 (lam p2 (gt? (fst p1) (fst p2)))) scored)))))))))))))

