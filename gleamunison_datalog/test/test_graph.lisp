;; ─────────────────────────────────────────────────────────────────────────────
;; test_graph.lisp — Graph traversal and algorithm tests
;; Requires: 10_graph.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; Build a small test graph:
;; 1 ──link──> 2 ──link──> 3
;; 1 ────────link────────> 3
(define make-test-graph
  (lam dummy
    (let db (db-assert db-empty 1 "link" 2)
      (let db (db-assert db 2 "link" 3)
        (db-assert db 1 "link" 3)))))

(define test-bfs
  (lam dummy
    (let db (make-test-graph 0)
      (let visited (graph-bfs db 1 "link")
        ;; visited should contain 1, 2, 3 (order might vary depending on queue addition)
        (let l (list-length visited)
          (and (eq? l 3)
            (and (list-member? 1 visited)
              (and (list-member? 2 visited)
                (list-member? 3 visited)))))))))

(define test-dfs
  (lam dummy
    (let db (make-test-graph 0)
      (let visited (graph-dfs db 1 "link")
        (let l (list-length visited)
          (and (eq? l 3)
            (and (list-member? 1 visited)
              (and (list-member? 2 visited)
                (list-member? 3 visited)))))))))

(define test-shortest-path
  (lam dummy
    (let db (make-test-graph 0)
      ;; Direct path 1 -> 3 is shorter than 1 -> 2 -> 3
      (let path (graph-shortest-path db 1 3 "link")
        (eq? path (list 1 3))))))

(define run-graph-tests
  (lam dummy
    (list
      (assert-eq true (test-bfs 0) "test-bfs")
      (assert-eq true (test-dfs 0) "test-dfs")
      (assert-eq true (test-shortest-path 0) "test-shortest-path"))))
