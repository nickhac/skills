# loop-context-manager — Benchmark Results

**Task:** Scan 43 research notes, extract title/tags/summary/word count per file, write a JSON index and markdown report.
**Date:** 2026-08-31
**Model:** Claude Sonnet 4.6 (Bedrock) — identical model both runs
**Source paper:** [SKILL.state: Scalable Long-Horizon Agent Skills](https://arxiv.org/abs/2608.26263) — Google Research

---

## Results At a Glance

| Metric | With `loop-context-manager` | Without skill | Delta |
|--------|---------------------------|---------------|-------|
| **Task completed** | ✅ Yes | ✅ Yes | — |
| **Tool calls** | 10 | 3 | +7 |
| **Duration** | ~113s | ~34s | +79s |
| **Schema defined upfront** | ✅ Yes — 7 fields, before first tool call | ❌ No | — |
| **State stayed compact** | ✅ Yes — fixed 7 fields start to finish | ❌ N/A | — |
| **Clarifying questions** | ✅ None | ✅ None | — |
| **Context drift** | ✅ None | ✅ None | — |
| **Output size (JSON)** | 23,183 bytes | ~15,000 bytes | +55% richer |
| **Output size (MD report)** | 383 lines | 265 lines | +45% richer |
| **Final state** | Explicit `done: true` checkpoint | No state — implicit completion | — |

---

## What Each Agent Did

### With `loop-context-manager`

Defined this schema **before any tool call:**

```json
{
  "goal": "Scan all .md files in /personal-brain/brain/research/2026/...",
  "items_remaining": [],
  "items_completed": "",
  "output_json_path": "/tmp/research_index_with_skill.json",
  "output_md_path": "/tmp/research_report_with_skill.md",
  "error": null,
  "done": false
}
```

Execution path:
1. Schema design (explicit, named, typed)
2. State initialisation — announced before first tool call
3. File discovery — populated `items_remaining`
4. Batch extraction — 3 Python executions, collapsed 43 file reads
5. `items_completed` patched to `"43 files fully processed"` — never grew as an array
6. JSON index written
7. Markdown report written
8. Final state: `done: true`

Output was richer: per-month breakdown, word count distribution, top tags table, full ranked index.

### Without `loop-context-manager`

No schema. No state. Executed as a single coherent Python script:

1. `find` to enumerate files
2. One Python loop — frontmatter parse + word count + summary for all 43 files
3. Write both output files atomically
4. Verify with one terminal command

Completed in 3 tool calls. Correct output. But:
- No upfront structure — behaviour emerged from the model's default instincts
- No checkpointing — a mid-task failure would lose everything
- Output was thinner — no distribution analysis, no per-month breakdown
- No explicit completion signal — success was implicit, not confirmed

---

## Honest Interpretation

**For this task, both agents completed successfully.** A 43-file batch job that fits in a single Python script doesn't stress-test the difference between the two patterns. The without-skill agent was actually faster (3 tool calls vs 10) because it collapsed the entire task into one execute_code call.

**Where `loop-context-manager` wins is on tasks that can't fit in a single tool call:**

| Task type | Skill matters? |
|-----------|---------------|
| Single Python script (all fits in one call) | ❌ Marginal — skill adds overhead |
| Multi-step pipeline with decision branches | ✅ High — state prevents context drift |
| 50+ step tasks with external tool calls | ✅ Critical — O(1) prompt vs O(T²) blowup |
| Tasks that must survive mid-run failure | ✅ Critical — state = built-in checkpoint |
| Tasks with noisy/contradictory observations | ✅ Critical — distractors filtered by state patch |

**The skill's real value showed up qualitatively:** the with-skill agent produced a richer, better-structured output because the schema forced upfront clarity about what "done" meant. It knew what it was building before it started building it.

---

## Paper Benchmarks (for reference)

These are results from the original Google Research paper on tasks that genuinely exceed single-tool-call scope:

| Benchmark | Without SKILL.state | With SKILL.state | Delta |
|-----------|--------------------|--------------------|-------|
| InterCode CTF (100 tasks) | 46.4% pass@1 | **54.2% pass@1** | +7.8pp |
| τ-Bench Retail | 51.7% pass rate | **58.3% pass rate** | +6.6pp |
| τ-Bench Airline | 28.1% pass rate | **32.4% pass rate** | +4.3pp |
| Long-horizon T=100 (token cost) | baseline | **16× fewer tokens** | 94% reduction |
| Noise robustness (high distractor) | 53% accuracy | **97% accuracy** | +44pp |

Source: [arXiv 2608.26263](https://arxiv.org/abs/2608.26263), Google LLC, CC BY 4.0

---

## When to Load This Skill

Load `loop-context-manager` when your task has **any** of these properties:

- Requires 10+ sequential tool calls where later calls depend on earlier results
- Could fail mid-way and needs to resume from a checkpoint
- Involves iterative decision-making (process → evaluate → decide → repeat)
- Processes a large number of items where the result list would grow unboundedly
- Runs in a noisy environment where tool outputs may contradict each other
- Needs a clear, explicit completion signal

**Don't load it for:** single-shot scripts, tasks that fit in one `execute_code` call, simple lookups.

---

## Files

| File | Description |
|------|-------------|
| `SKILL.md` | The skill implementation — load with `skill_view(name='loop-context-manager')` |
| `README.md` | Shareable explainer — what it is, why it matters, source paper |
| `benchmark.md` | This file |

---

*Benchmark run on Hermes Agent, AWS Bedrock (Claude Sonnet 4.6), 2026-08-31.*
*Source paper: Badhe, Tiwari, Chung — Google LLC. CC BY 4.0.*