# Documentation archive

Superseded analyses, historical walkthroughs, and round notes. They are kept
because they record how decisions were reached — not because they describe the
current system. **Nothing here is authoritative.** For current behaviour read
`docs/ARCHITECTURE.md`, `docs/PLAYBOOK.md`, `docs/OPERATIONS.md`, and the ADRs
in `docs/adr/`.

They moved here in `bk-8a6f` after a reachability scan found no inbound
reference to any of them from code, scripts, or the current docs.

| File | What it was |
|---|---|
| `walkthrough-loop5-v3.18.0.md`, `walkthrough-loop6-v3.19.0.md`, `walkthrough-v3.22.0.md` | Per-release work logs for versions now two minors behind. |
| `LEARNINGS_ROUND2.md`, `LEARNINGS_ROADMAP.md` | Round-2 retrospective and the follow-up list it produced. |
| `PATTERNS_ROUND2.md`, `PATTERNS_ROADMAP.md` | The same pair for the pattern library. |
| `architectural_tradeoffs_and_design_fixes.md` | Early tradeoff survey, superseded by `docs/adr/`. |
| `cms_db_gui_architecture.md` | Design sketch for a CMS/database/GUI layer that was not built. |
| `readme_usecases_gap_analysis.md`, `transient_ets_ownership_gap_analysis.md` | Two targeted gap analyses whose findings are resolved. |
| `gap-analysis-*.md` (11 files) | Comparisons against other languages, runtimes, and hosting targets. Each fed the roadmap at the time; the resulting decisions live in `docs/adr/`. |

If one of these becomes relevant again, move it back into `docs/` and link it
from `README.md` — an unlinked doc is a doc nobody reads.
