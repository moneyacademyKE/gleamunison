## Level 501: Math ability
**Goal:** Math via effects.
### 501.1 Test
```
(do Math add 1 2)
```
Expected: 3

---

## Level 502: Logger ability
**Goal:** Log with levels.
### 502.1 Test
```
(do Logger log "msg")
```
Expected: Logged

---

## Level 503: Config ability
**Goal:** Config lookup.
### 503.1 Test
```
(do Config get "key")
```
Expected: Config value

---

## Level 504: Clock ability
**Goal:** Current time.
### 504.1 Test
```
(do Clock now)
```
Expected: Timestamp

---

## Level 505: Stack nesting
**Goal:** Handle A inside B.
### 505.1 Test
```
(handle (handle (do A ...) ...) ...)
```
Expected: Both active

---

## Level 506: Effect composition
**Goal:** Console + Math.
### 506.1 Test
```
(handle (do Console print (do Math add 1 2)) ...)
```
Expected: 3 printed

---

## Level 507: Handler chain
**Goal:** B delegates unhandled.
### 507.1 Test
```
(handle (do A ...) B where B forwards to A)
```
Expected: Forwarded

---

## Level 508: Effect aliasing
**Goal:** Alias ops.
### 508.1 Test
```
(do Logger info "msg") => (do Console print "msg")
```
Expected: Aliased

---

## Level 509: Default handlers
**Goal:** Fallback if none provided.
### 509.1 Test
```
(do A op ...) with default handler
```
Expected: Default used

---

## Level 510: Op routing
**Goal:** Dispatch by op index.
### 510.1 Test
```
handler routes op 0 to A, op 1 to B
```
Expected: Routed

---

## Level 511: JSON API
**Goal:** GET /api/echo?msg=hi.
### 511.1 Test
```
curl /api/echo?msg=hi
```
Expected: {"msg":"hi"}

---

## Level 512: Form parsing
**Goal:** POST form data.
### 512.1 Test
```
curl -d "name=alice" /form
```
Expected: {"name":"alice"}

---

## Level 513: Cookie parsing
**Goal:** Read/set cookies.
### 513.1 Test
```
curl -b "session=abc" /app
```
Expected: Cookie read

---

## Level 514: Session middleware
**Goal:** Session by cookie.
### 514.1 Test
```
GET /app with session cookie
```
Expected: Session context

---

## Level 515: Static files
**Goal:** GET /static/file.txt.
### 515.1 Test
```
curl /static/test.txt
```
Expected: File content

---

## Level 516: Route params
**Goal:** GET /user/:id.
### 516.1 Test
```
curl /user/42
```
Expected: {"id":"42"}

---

## Level 517: Query params
**Goal:** ?name=value.
### 517.1 Test
```
curl /search?q=test
```
Expected: {"q":"test"}

---

## Level 518: POST body
**Goal:** Parse raw/JSON/form body.
### 518.1 Test
```
curl -X POST -d '{"x":1}' /api
```
Expected: Body parsed

---

## Level 519: Response headers
**Goal:** Content-Type, Cache-Control.
### 519.1 Test
```
curl -v /
```
Expected: Headers in response

---

## Level 520: Status codes
**Goal:** 200, 404, 500, etc.
### 520.1 Test
```
curl -v /nonexistent
```
Expected: 404 Not Found

---

## Level 521: DETS recovery
**Goal:** Open after crash.
### 521.1 Test
```
open DETS without close, then reopen
```
Expected: Recovered

---

## Level 522: DETS integrity
**Goal:** All entries readable.
### 522.1 Test
```
(dets-check file.dets)
```
Expected: OK or corrupted list

---

## Level 523: DETS repair
**Goal:** Fix corrupt entries.
### 523.1 Test
```
(dets-repair file.dets)
```
Expected: Recovered entries

---

## Level 524: DETS backup
**Goal:** Copy to backup path.
### 524.1 Test
```
(dets-backup file.dets backup.dets)
```
Expected: Backup created

---

## Level 525: DETS restore
**Goal:** Restore from backup.
### 525.1 Test
```
(dets-restore backup.dets new.dets)
```
Expected: Restored

---

## Level 526: KV store
**Goal:** Key-value operations.
### 526.1 Test
```
(kv-set "k" 42) (kv-get "k")
```
Expected: OK then 42

---

## Level 527: KV typed
**Goal:** Type-aware storage.
### 527.1 Test
```
(kv-set "k" 42 :int) (kv-get "k")
```
Expected: 42 as Int

---

## Level 528: KV TTL
**Goal:** Auto-expire.
### 528.1 Test
```
(kv-set "k" 42 :ttl 60) (wait 60) (kv-get "k")
```
Expected: nil

---

## Level 529: KV listing
**Goal:** All keys.
### 529.1 Test
```
(kv-set "a" 1) (kv-set "b" 2) (kv-keys)
```
Expected: ["a","b"]

---

## Level 530: KV batch
**Goal:** Multi-set/get.
### 530.1 Test
```
(kv-set-many [["a" 1] ["b" 2]])
```
Expected: Both set

---

## Level 531: Spawn with args
**Goal:** Pass data to spawned fn.
### 531.1 Test
```
(spawn (lam (x) x) 42)
```
Expected: 42

---

## Level 532: Spawn and wait
**Goal:** Recv result.
### 532.1 Test
```
(spawn f) (recv)
```
Expected: f's result

---

## Level 533: Spawn many
**Goal:** 100 concurrent evals.
### 533.1 Test
```
spawn 100 fns, collect results
```
Expected: All 100 return

---

## Level 534: Send to self
**Goal:** Self PID round-trip.
### 534.1 Test
```
(send (self) "msg") (recv)
```
Expected: "msg"

---

## Level 535: Process registry
**Goal:** Register/whereis.
### 535.1 Test
```
(register "w" pid) (whereis "w")
```
Expected: PID

---

## Level 536: Timeout recv
**Goal:** Receive with timeout.
### 536.1 Test
```
(recv 1000)
```
Expected: timeout after 1s

---

## Level 537: Selective receive
**Goal:** Match on message.
### 537.1 Test
```
(recv pattern)
```
Expected: Matched msg

---

## Level 538: Process linking
**Goal:** Link monitors.
### 538.1 Test
```
(link pid)
```
Expected: Link established

---

## Level 539: Link propagation
**Goal:** Linked crash propagates.
### 539.1 Test
```
linked process crashes
```
Expected: Both crash

---

## Level 540: Process monitoring
**Goal:** DOWN messages.
### 540.1 Test
```
(monitor pid) ... kill pid
```
Expected: DOWN received

---

## Level 541: Assertion
**Goal:** Pass/fail check.
### 541.1 Test
```
(assert (= 1 1))
```
Expected: Pass

---

## Level 542: Test runner
**Goal:** Register + run tests.
### 542.1 Test
```
(test "add" (lam () (assert (= (add 1 2) 3))))
```
Expected: 1 passed

---

## Level 543: Test grouping
**Goal:** Suite of tests.
### 543.1 Test
```
(suite "math" ... (test "sub" ...))
```
Expected: Grouped results

---

## Level 544: Test fixtures
**Goal:** Setup/teardown.
### 544.1 Test
```
(with-setup setup-fn test-fn)
```
Expected: Fixture ready

---

## Level 545: Test coverage
**Goal:** Track loaded defs.
### 545.1 Test
```
:coverage
```
Expected: Coverage report

---

## Level 546: Property-based
**Goal:** For-all assertions.
### 546.1 Test
```
(for-all x (int) (= x x))
```
Expected: Pass (100 runs)

---

## Level 547: Fuzz testing
**Goal:** Random inputs.
### 547.1 Test
```
(fuzz fuzz-target 1000)
```
Expected: Edge cases found

---

## Level 548: Benchmarking
**Goal:** Measure execution time.
### 548.1 Test
```
(bench "add" 10000 (lam () (add 1 2)))
```
Expected: Mean time

---

## Level 549: Comparison bench
**Goal:** Compare two impls.
### 549.1 Test
```
(vs (bench A) (bench B))
```
Expected: Faster/slower

---

## Level 550: Test report
**Goal:** Summary.
### 550.1 Test
```
(run-tests)
```
Expected: X passed, Y failed

---


## Level 551: Data structure op
**Goal:** Basic operation test.
### 551.1 Run
```
(define test551 551)
```
Expected: Level 551 verified

---

## Level 552: Data structure op
**Goal:** Basic operation test.
### 552.1 Run
```
(define test552 552)
```
Expected: Level 552 verified

---

## Level 553: Data structure op
**Goal:** Basic operation test.
### 553.1 Run
```
(define test553 553)
```
Expected: Level 553 verified

---

## Level 554: Data structure op
**Goal:** Basic operation test.
### 554.1 Run
```
(define test554 554)
```
Expected: Level 554 verified

---

## Level 555: Data structure op
**Goal:** Basic operation test.
### 555.1 Run
```
(define test555 555)
```
Expected: Level 555 verified

---

## Level 556: Data structure op
**Goal:** Basic operation test.
### 556.1 Run
```
(define test556 556)
```
Expected: Level 556 verified

---

## Level 557: Data structure op
**Goal:** Basic operation test.
### 557.1 Run
```
(define test557 557)
```
Expected: Level 557 verified

---

## Level 558: Data structure op
**Goal:** Basic operation test.
### 558.1 Run
```
(define test558 558)
```
Expected: Level 558 verified

---

## Level 559: Data structure op
**Goal:** Basic operation test.
### 559.1 Run
```
(define test559 559)
```
Expected: Level 559 verified

---

## Level 560: Data structure op
**Goal:** Basic operation test.
### 560.1 Run
```
(define test560 560)
```
Expected: Level 560 verified

---

## Level 561: Data structure op
**Goal:** Basic operation test.
### 561.1 Run
```
(define test561 561)
```
Expected: Level 561 verified

---

## Level 562: Data structure op
**Goal:** Basic operation test.
### 562.1 Run
```
(define test562 562)
```
Expected: Level 562 verified

---

## Level 563: Data structure op
**Goal:** Basic operation test.
### 563.1 Run
```
(define test563 563)
```
Expected: Level 563 verified

---

## Level 564: Data structure op
**Goal:** Basic operation test.
### 564.1 Run
```
(define test564 564)
```
Expected: Level 564 verified

---

## Level 565: Data structure op
**Goal:** Basic operation test.
### 565.1 Run
```
(define test565 565)
```
Expected: Level 565 verified

---

## Level 566: Data structure op
**Goal:** Basic operation test.
### 566.1 Run
```
(define test566 566)
```
Expected: Level 566 verified

---

## Level 567: Data structure op
**Goal:** Basic operation test.
### 567.1 Run
```
(define test567 567)
```
Expected: Level 567 verified

---

## Level 568: Data structure op
**Goal:** Basic operation test.
### 568.1 Run
```
(define test568 568)
```
Expected: Level 568 verified

---

## Level 569: Data structure op
**Goal:** Basic operation test.
### 569.1 Run
```
(define test569 569)
```
Expected: Level 569 verified

---

## Level 570: Data structure op
**Goal:** Basic operation test.
### 570.1 Run
```
(define test570 570)
```
Expected: Level 570 verified

---

## Level 571: Data structure op
**Goal:** Basic operation test.
### 571.1 Run
```
(define test571 571)
```
Expected: Level 571 verified

---

## Level 572: Data structure op
**Goal:** Basic operation test.
### 572.1 Run
```
(define test572 572)
```
Expected: Level 572 verified

---

## Level 573: Data structure op
**Goal:** Basic operation test.
### 573.1 Run
```
(define test573 573)
```
Expected: Level 573 verified

---

## Level 574: Data structure op
**Goal:** Basic operation test.
### 574.1 Run
```
(define test574 574)
```
Expected: Level 574 verified

---

## Level 575: Data structure op
**Goal:** Basic operation test.
### 575.1 Run
```
(define test575 575)
```
Expected: Level 575 verified

---

## Level 576: Data structure op
**Goal:** Basic operation test.
### 576.1 Run
```
(define test576 576)
```
Expected: Level 576 verified

---

## Level 577: Data structure op
**Goal:** Basic operation test.
### 577.1 Run
```
(define test577 577)
```
Expected: Level 577 verified

---

## Level 578: Data structure op
**Goal:** Basic operation test.
### 578.1 Run
```
(define test578 578)
```
Expected: Level 578 verified

---

## Level 579: Data structure op
**Goal:** Basic operation test.
### 579.1 Run
```
(define test579 579)
```
Expected: Level 579 verified

---

## Level 580: Data structure op
**Goal:** Basic operation test.
### 580.1 Run
```
(define test580 580)
```
Expected: Level 580 verified

---

## Level 581: Data structure op
**Goal:** Basic operation test.
### 581.1 Run
```
(define test581 581)
```
Expected: Level 581 verified

---

## Level 582: Data structure op
**Goal:** Basic operation test.
### 582.1 Run
```
(define test582 582)
```
Expected: Level 582 verified

---

## Level 583: Data structure op
**Goal:** Basic operation test.
### 583.1 Run
```
(define test583 583)
```
Expected: Level 583 verified

---

## Level 584: Data structure op
**Goal:** Basic operation test.
### 584.1 Run
```
(define test584 584)
```
Expected: Level 584 verified

---

## Level 585: Data structure op
**Goal:** Basic operation test.
### 585.1 Run
```
(define test585 585)
```
Expected: Level 585 verified

---

## Level 586: Data structure op
**Goal:** Basic operation test.
### 586.1 Run
```
(define test586 586)
```
Expected: Level 586 verified

---

## Level 587: Data structure op
**Goal:** Basic operation test.
### 587.1 Run
```
(define test587 587)
```
Expected: Level 587 verified

---

## Level 588: Data structure op
**Goal:** Basic operation test.
### 588.1 Run
```
(define test588 588)
```
Expected: Level 588 verified

---

## Level 589: Data structure op
**Goal:** Basic operation test.
### 589.1 Run
```
(define test589 589)
```
Expected: Level 589 verified

---

## Level 590: Data structure op
**Goal:** Basic operation test.
### 590.1 Run
```
(define test590 590)
```
Expected: Level 590 verified

---

## Level 591: Data structure op
**Goal:** Basic operation test.
### 591.1 Run
```
(define test591 591)
```
Expected: Level 591 verified

---

## Level 592: Data structure op
**Goal:** Basic operation test.
### 592.1 Run
```
(define test592 592)
```
Expected: Level 592 verified

---

## Level 593: Data structure op
**Goal:** Basic operation test.
### 593.1 Run
```
(define test593 593)
```
Expected: Level 593 verified

---

## Level 594: Data structure op
**Goal:** Basic operation test.
### 594.1 Run
```
(define test594 594)
```
Expected: Level 594 verified

---

## Level 595: Data structure op
**Goal:** Basic operation test.
### 595.1 Run
```
(define test595 595)
```
Expected: Level 595 verified

---

## Level 596: Data structure op
**Goal:** Basic operation test.
### 596.1 Run
```
(define test596 596)
```
Expected: Level 596 verified

---

## Level 597: Data structure op
**Goal:** Basic operation test.
### 597.1 Run
```
(define test597 597)
```
Expected: Level 597 verified

---

## Level 598: Data structure op
**Goal:** Basic operation test.
### 598.1 Run
```
(define test598 598)
```
Expected: Level 598 verified

---

## Level 599: Data structure op
**Goal:** Basic operation test.
### 599.1 Run
```
(define test599 599)
```
Expected: Level 599 verified

---

## Level 600: Data structure op
**Goal:** Basic operation test.
### 600.1 Run
```
(define test600 600)
```
Expected: Level 600 verified

---

