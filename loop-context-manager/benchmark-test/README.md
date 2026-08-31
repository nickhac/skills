# benchmark-test

Code for reproducing the loop-context-manager A/B benchmark.

## Files

| File | Purpose |
|------|---------|
| `run_benchmark.sh` | Full A/B runner — runs both agents, captures session IDs, measures tokens |
| `task_prompt.txt` | The benchmark task — sequential per-file audit that forces 20+ turns |
| `token_measure.py` | Reads the Hermes state DB and reports per-session token usage |

## Running the benchmark

```bash
cd /path/to/benchmark-test
bash run_benchmark.sh
```

Optional: pass a different target directory:
```bash
bash run_benchmark.sh /your/vault/folder/
```

Output lands in `/tmp/lcm_bench_<timestamp>/`:
- `run_with_skill.log` — full agent transcript (with skill)
- `run_no_skill.log` — full agent transcript (without skill)
- `tokens_with_skill.txt` — token report (with skill)
- `tokens_no_skill.txt` — token report (without skill)

## What makes this a valid benchmark

The task is designed to force sequential per-file decisions that cannot be batched:
- Each file is a separate tool call
- Each result changes the running tally before the next step
- Periodic checkpoint writes create real turn-by-turn dependency

This is what surfaces the O(T²) context accumulation problem in standard ReAct agents.
The skill keeps prompt size flat by discarding reasoning after each state patch.

## Measuring what matters

The key metric is **cache read tokens** — what the model pays to re-read accumulated context on every turn.
Standard ReAct: cache reads compound with every turn (O(T²)).
With loop-context-manager: cache reads stay bounded (O(1) per step).

From the reference run (2026-08-31):
- With skill: 696,542 cache read tokens, 19 API calls, task **complete**
- Without skill: 4,274,282 cache read tokens, 90 API calls, task **failed at 25%**
