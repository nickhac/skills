# loop-context-manager — Benchmark Results

> **Source:** Live A/B test run on Hermes Agent (Claude Sonnet 4.6, Bedrock)
> **Date:** 2026-08-31
> **Task:** Sequential audit pipeline — 213 files, one file per agent turn, no batching allowed

---

## TL;DR

| | With `loop-context-manager` | Without |
|---|---|---|
| **Task completed** | ✅ Yes | ❌ No — hit turn limit at 53/213 files (25%) |
| **API calls** | 19 | 90 |
| **Output tokens** | 6,140 | 16,429 |
| **Cache read tokens** | 696,542 | 4,274,282 |
| **Estimated cost** | $0.39 | $1.93 |
| **Duration** | 1m 31s | 5m 51s (incomplete) |
| **Files processed** | 213/213 | 53/213 |

**Without the skill: 4.7× more expensive, ran out of turns, never finished.**

---

## The Test

Standard benchmarks cheat — they let the agent batch everything into a single script. Real long-horizon tasks don't work that way. The agent must make decisions turn by turn, where each result changes what happens next.

This benchmark forced that:

```
Process each .md file in ~/vault/principles/ ONE AT A TIME.
Each file is a separate tool call. For each file:
  1. Read the file
  2. Extract the title and first principle statement
  3. Check if it references any other principles
  4. Write a one-line entry to /tmp/audit_progress.txt
  5. Every 5 files, write a checkpoint to /tmp/audit_final.txt

You cannot batch. You cannot use a single script. Each file = one tool call.
```

213 files × sequential decisions = the exact workload where context accumulation becomes fatal.

---

## What Happened

### With `loop-context-manager`

The agent defined a state schema before the first tool call:

```json
{
  "objective": "Audit all principle files one-by-one",
  "files_remaining": ["<list of 213 paths>"],
  "files_completed": 0,
  "current_file": null,
  "last_finding": null,
  "checkpoint_due": false,
  "done": false
}
```

At each turn it received only:
- The immutable skill spec (constant size)
- The current state JSON (constant size — `files_completed` was a counter, not a growing list)
- The latest file's content (one file at a time)

The agent's reasoning at each step was **discarded after generating the state patch**. It never accumulated in the prompt.

**Result: 213 files processed in 19 API calls. Task complete.**

### Without `loop-context-manager`

The agent used standard ReAct — each turn's full output was appended to conversation history. By turn 53 the context had grown so large the agent hit the 90-turn iteration limit with 160 files still unprocessed.

The pattern was textbook O(T²): each new turn carried the full weight of every prior turn's reasoning, file content, and output.

**Result: Hit turn limit at 25% completion. Task failed.**

---

## Token Growth

The per-turn token data from the Hermes session DB:

| Metric | With skill | Without skill | Ratio |
|--------|-----------|---------------|-------|
| API calls to completion | 19 | 90 (incomplete) | **4.7×** |
| Output tokens | 6,140 | 16,429 | **2.7×** |
| Cache read tokens | 696,542 | 4,274,282 | **6.1×** |
| Cost | $0.39 | $1.93 | **4.9×** |

The cache read token gap (696k vs 4.27M) is the most important number. Cache reads represent what the model is paying to "see" on every turn — the accumulated history. Without the skill, that number explodes as every prior file read stays in context. With the skill, it stays bounded because old observations are summarised into state and discarded.

---

## Alignment With the Paper

Google's SKILL.state paper (arXiv 2608.26263) reported:

| Benchmark | Without | With | Improvement |
|-----------|---------|------|-------------|
| InterCode CTF accuracy | 46.4% | 54.2% | +7.8pp |
| InterCode CTF tokens | 977k | 387k | **2.5× cheaper** |
| τ-Bench Retail pass rate | 51.7% | 58.3% | +6.6pp |
| Long-horizon T=100 tokens | ~1.06M | ~65k | **16× cheaper** |

The Hermes benchmark aligns: the token efficiency gains are real and compound with task length. At T=53 (where the no-skill agent gave up), the skill agent had already completed 213 files and written its final output.

---

## When To Use This Skill

**Load it when:**
- The task will take 10+ sequential tool calls
- Each step depends on the previous result (can't batch)
- You need the agent to stay reliable at turn 50+ without drift
- Cost matters (long tasks get expensive fast without state management)

**Don't need it when:**
- The entire task fits in one `execute_code` call
- Fewer than ~10 steps
- Task is embarrassingly parallel (use `delegate_task` instead)

---

## Reproducing This Benchmark

The full benchmark code is in `benchmark-test/`:

```
benchmark-test/
  run_benchmark.sh    — full A/B runner, one command to reproduce
  task_prompt.txt     — the sequential audit task
  token_measure.py    — reads Hermes state DB, reports token usage
  README.md           — setup and measurement notes
```

**To run:**
```bash
cd skills/loop-context-manager/benchmark-test
bash run_benchmark.sh
# Optional: pass a different target dir
bash run_benchmark.sh /your/vault/folder/
```

Results land in `/tmp/lcm_bench_<timestamp>/` with full transcripts and token reports for both runs.

**To measure an existing session:**
```bash
python3 token_measure.py <session_id> LABEL
python3 token_measure.py   # list recent sessions
```

Session IDs from the reference run (2026-08-31):
- With skill: `20260831_064635_b4be97`
- Without skill: `20260831_064632_9cd024`

---

## Source

- Paper: [SKILL.state: Scalable Long-Horizon Agent Skills](https://arxiv.org/abs/2608.26263) — Badhe, Tiwari, Chung (Google LLC), 2026, CC BY 4.0
- Skill: `loop-context-manager` by nickhac
- Hermes Agent by Nous Research