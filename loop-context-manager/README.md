# loop-context-manager

**Keep your agent's prompt flat at any task length. No context blowup. No history accumulation. No drift.**

---

## What is this?

This skill encodes a better way to run long-horizon AI agents — tasks that require 10, 50, or 200+ sequential steps.

Standard AI agent loops (ReAct, MemGPT, LangGraph) append every observation, reasoning trace, and action to a growing conversation history. The problem: at 50+ steps the context window bloats, old facts override new observations, and costs spiral. This is why most agentic workflows feel unreliable at scale.

**SKILL.state** replaces the transcript with a small, explicit, mutable JSON state object — the minimal set of facts needed to decide the next action. At every step, the model sees only:

1. **The skill specification** — what we're doing and what the state fields mean (loaded once, never changes)
2. **The current state** — a compact JSON object representing everything known so far
3. **The latest observation** — only the most recent tool output

The model reasons, generates a JSON patch to update the state, picks the next action — then the reasoning is **discarded**. Only the state update persists. No prior turns ever re-enter the prompt.

The result: a constant-size prompt at every step, regardless of how long the task has been running.

---

## Why it matters

The results from the paper are striking:

| Scenario | Standard Agent | SKILL.state | Improvement |
|----------|---------------|-------------|-------------|
| Long task (T=100 steps) | 1,245,413 tokens | 65,408 tokens | **19× cheaper** |
| Long task (T=100) accuracy | 84% | **94%** | +10pp |
| CTF security challenges | 46.4% pass rate | **54.2%** | +7.8pp |
| Enterprise workflows (retail) | 51.7% | **58.3%** | +6.6pp |
| High-noise environments | 53% accuracy | **97%** | Robust |

More accurate AND dramatically cheaper. The gains compound as task length grows.

The **noise robustness result** is particularly important: standard agents exposed to distractor observations degrade badly because every distractor is permanently in the history. SKILL.state filters distractors at patch-generation time and they never re-enter future prompts.

---

## How to use this skill

Load it in Hermes when designing or implementing a multi-step agentic workflow:

```
skill_view(name='loop-context-manager')
```

The skill provides:
- The three-part prompt structure (P + Σ_t + O_t)
- Schema design rules (5–7 fields, decision-surface not log)
- Example schemas for research, code, and pipeline tasks
- The patch format (JSON diff with null-deletion semantics)
- An implementation loop pattern
- A ready-to-use Hermes prompt template
- Constrained decoding guidance for smaller models
- A full pitfalls and verification checklist

---

## When to apply it

**Good candidates:**
- Any skill that runs 10+ sequential tool calls
- Vault ingestion pipelines with multiple stages
- Research workflows that accumulate findings over many sources
- Code tasks that touch multiple files with dependencies
- Long-running cron jobs that manage state across iterations
- Any task where you've hit "context too long" or noticed quality degrading mid-run

**Not suitable for:**
- Short 2–5 step tasks (overhead not worth it)
- Tasks where the full interaction history is the output (audit logs, provenance)
- Tasks where the state structure can't be defined in advance

---

## Source

This skill is a direct implementation of:

> **SKILL.state: Scalable Long-Horizon Agent Skills**
> Sanket Badhe, Priyanka Tiwari, Jonghyun Chung
> Google LLC / Purdue University
> arXiv: https://arxiv.org/abs/2608.26263
> License: CC BY 4.0

The paper introduces both the SKILL.state architecture and **SkillExecBench** — a new controlled benchmark for evaluating long-horizon procedural skill execution across Warehouse Management and Software Repository environments. Validated across Gemini-3-Flash, Gemma-4-31B, and Qwen-3-8B.

---

## Files

```
skills/loop-context-manager/
├── SKILL.md     — Full skill: design rules, prompt templates, patterns, pitfalls
└── README.md    — This file
```

---

## Author

Skill authored by Hermes Agent for Nick Holmes à Court's personal brain vault.
Based on Google Research paper (CC BY 4.0).