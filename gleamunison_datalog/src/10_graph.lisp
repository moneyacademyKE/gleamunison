;; ─────────────────────────────────────────────────────────────────────────────
;; 10_graph.lisp — Graph algorithms (BFS, DFS, Shortest Path, PageRank)
;; Requires: 01_core.lisp, 02_index.lisp
;; ─────────────────────────────────────────────────────────────────────────────

;; Helper: get outgoing neighbors of a node along an attribute/edge-type
(define graph-neighbors
  (lam db (lam node (lam edge-attr
    (eavt-attr-vals (db-eavt db) node edge-attr)))))

;; ── BFS (Breadth-First Search) ───────────────────────────────────────────────
;; (graph-bfs db start edge-attr) → list of visited nodes
(define graph-bfs
  (lam db (lam start (lam edge-attr
    (let bfs-loop
      (lam self (lam queue (lam visited
        (if (eq? queue (list))
          visited
          (let current (list-head queue)
            (let rest-queue (list-tail queue)
              (if (list-member? current visited)
                (self self rest-queue visited)
                (let neighbors (graph-neighbors db current edge-attr)
                  (let new-queue (list-append rest-queue neighbors)
                    (let new-visited (cons current visited)
                      (self self new-queue new-visited)))))))))))
      (list-reverse (bfs-loop bfs-loop (list start) (list))))))))

;; ── DFS (Depth-First Search) ─────────────────────────────────────────────────
;; (graph-dfs db start edge-attr) → list of visited nodes
(define graph-dfs
  (lam db (lam start (lam edge-attr
    (let dfs-loop
      (lam self (lam stack (lam visited
        (if (eq? stack (list))
          visited
          (let current (list-head stack)
            (let rest-stack (list-tail stack)
              (if (list-member? current visited)
                (self self rest-stack visited)
                (let neighbors (graph-neighbors db current edge-attr)
                  ;; Prepend neighbors to stack for depth-first ordering
                  (let new-stack (list-append neighbors rest-stack)
                    (let new-visited (cons current visited)
                      (self self new-stack new-visited)))))))))))
      (list-reverse (dfs-loop dfs-loop (list start) (list))))))))

;; ── Shortest Path (BFS-based) ────────────────────────────────────────────────
;; Returns list representing shortest path from start to target node
(define graph-shortest-path
  (lam db (lam start (lam target (lam edge-attr
    (let path-loop
      (lam self (lam queue (lam visited
        (if (eq? queue (list))
          (list)
          (let current-path (list-head queue)
            (let current-node (list-head current-path)
              (let rest-queue (list-tail queue)
                (if (eq? current-node target)
                  (list-reverse current-path)
                  (if (list-member? current-node visited)
                    (self self rest-queue visited)
                    (let neighbors (graph-neighbors db current-node edge-attr)
                      (let neighbor-paths
                        (list-map
                          (lam n (cons n current-path))
                          neighbors)
                        (let new-queue (list-append rest-queue neighbor-paths)
                          (let new-visited (cons current-node visited)
                            (self self new-queue new-visited))))))))))))))
      (path-loop path-loop (list (list start)) (list))))))))

;; ── PageRank (Simplified Power Iteration) ────────────────────────────────────
;; Performs 3 iterations of PageRank over all nodes with a given edge-attr.
(define graph-pagerank
  (lam db (lam nodes (lam edge-attr
    (let initial-ranks
      (list-fold
        (lam acc (lam n (dict-set acc n 100)))
        (dict-new)
        nodes)
      (let iterate
        (lam self (lam iter (lam ranks
          (if (eq? iter 0)
            ranks
            (let new-ranks
              (list-fold
                (lam acc-ranks (lam node
                  (let neighbors (graph-neighbors db node edge-attr)
                    (let num-neighbors (list-length neighbors)
                      (if (eq? num-neighbors 0)
                        acc-ranks
                        (let current-rank (dict-safe-get ranks node 0)
                          (let share (div current-rank num-neighbors)
                            (list-fold
                              (lam r-acc (lam neighbor
                                (let old-r (dict-safe-get r-acc neighbor 0)
                                  (dict-set r-acc neighbor (add old-r share)))))
                              acc-ranks
                              neighbors))))))))
                (dict-new)
                nodes)
              (self self (sub iter 1) new-ranks))))))
        (iterate iterate 3 initial-ranks)))))))



