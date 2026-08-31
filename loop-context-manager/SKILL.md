---
name: loop-context-manager
description: Use when building multi-step agentic loops (10+ tool calls). Keeps prompt size flat at any task length — no context blowup, no history accumulation, no drift.
version: 2.0.0
author: nickhac
license: MIT
metadata:
  hermes:
    tags: [agents, long-horizon, state-management, token-efficiency, architecture]
---

# loop-context-manager

Source: Google Research, arXiv 2608.26263. 16× fewer tokens at T=100, higher accuracy than ReAct on all benchmarks.

The rule: **at each step the agent sees only three things — the skill spec, the current state JSON, and the latest observation. Nothing else. All reasoning is discarded after each step.**

---

## Step 1 — Design the state schema FIRST

Before writing a single line of code, define the JSON state object. Do this out loud in your response before any tool call.

**Schema rules:**
- 5–7 fields only. More than 8 and the model makes more patch errors than it fixes.
- Every field must answer: "does the agent need this to decide what to do next?" If no — cut it.
- Name fields for their current role, not their history. `active_blocker` not `blockers_encountered`.
- Always include a `done` boolean as the terminal signal.
- Types: strings, numbers, booleans, flat arrays of strings. No deep nesting.

**Templates to start from:**

Research / investigation task:
```json
{
  "goal": "string — the objective, set once, never changed",
  "sources_checked": [],
  "key_findings": [],
  "open_questions": [],
  "confidence": "low",
  "done": false
}
```

Code build / fix task:
```json
{
  "objective": "string — what we're building or fixing",
  "files_modified": [],
  "tests_passing": false,
  "current_blocker": null,
  "next_action": "string — what to do next",
  "done": false
}
```

Pipeline / ingestion task:
```json
{
  "input": "string — source file or URL",
  "stage": "fetch",
  "output_path": null,
  "errors": [],
  "retry_count": 0,
  "done": false
}
```

Multi-step data task:
```json
{
  "target": "string — what we're processing",
  "items_remaining": [],
  "items_completed": [],
  "last_result": null,
  "error": null,
  "done": false
}
```

---

## Step 2 — Initialise state and announce it

Before the first tool call, output the initial state explicitly:

```python
import json

state = {
    "goal": "...",        # fill in from task
    "sources_checked": [],
    "key_findings": [],
    "open_questions": ["<first question to answer>"],
    "confidence": "low",
    "done": False
}

print("Initial state:", json.dumps(state, indent=2))
```

This is the checkpoint. If the loop needs to be restarted, resume from this state.

---

## Step 3 — The loop

Each iteration of the loop must follow this exact structure:

```python
MAX_STEPS = 30  # set appropriate limit for the task

for step in range(MAX_STEPS):
    if state["done"]:
        break

    # --- BUILD THE STEP PROMPT ---
    # This is the ONLY thing the agent sees. No prior observations. No history.
    step_prompt = f"""
SKILL SPEC:
{SKILL_SPEC}  # the task description + schema field definitions

CURRENT STATE:
{json.dumps(state, indent=2)}

LATEST OBSERVATION:
{latest_observation}

Output exactly two things:
1. Brief reasoning (3-5 sentences): what does this observation mean for the current state?
2. A JSON patch: only the fields that changed. Use null to delete a field.

JSON patch:
```json
<patch here>
```
"""

    # --- EXECUTE ONE TOOL CALL ---
    latest_observation = execute_next_action(state)   # one tool call based on state

    # --- PARSE AND APPLY THE PATCH ---
    patch = extract_json_patch(model_response)
    state = apply_patch(state, patch)

    # reasoning is NOT saved anywhere — it produced the patch and is now gone
```

**The patch application function:**
```python
def apply_patch(state: dict, patch: dict) -> dict:
    result = dict(state)
    for key, value in patch.items():
        if value is None:
            result.pop(key, None)   # null = delete the field
        else:
            result[key] = value     # otherwise update
    return result
```

---

## Step 4 — Validate each patch before applying

Do not apply patches blindly. Check:

```python
def validate_patch(patch: dict, state: dict, schema_fields: list) -> bool:
    # 1. All keys in patch are known schema fields
    unknown = set(patch.keys()) - set(schema_fields)
    if unknown:
        print(f"WARNING: unknown fields in patch: {unknown}")
        return False

    # 2. Patch is not empty (model produced something)
    if not patch:
        print("WARNING: empty patch — model produced no state update")
        return False

    # 3. done field is boolean if present
    if "done" in patch and not isinstance(patch["done"], bool):
        print("WARNING: done field must be boolean")
        return False

    return True
```

If validation fails: log the bad patch, keep the previous state, retry the step once. If it fails twice — surface the error and stop.

---

## Step 5 — Handle JSON parse failures

The model will occasionally emit malformed JSON. Wrap parse in a repair fallback:

```python
import json

def extract_json_patch(text: str) -> dict:
    # 1. Try to extract from ```json ... ``` block
    import re
    match = re.search(r'```json\s*(.*?)\s*```', text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass

    # 2. Try raw_decode (handles trailing content)
    decoder = json.JSONDecoder()
    try:
        obj, _ = decoder.raw_decode(text)
        if isinstance(obj, dict):
            return obj
    except json.JSONDecodeError:
        pass

    # 3. Try json-repair if available
    try:
        from json_repair import repair_json
        return json.loads(repair_json(text))
    except Exception:
        pass

    # 4. Log and return empty patch (safe — keeps existing state)
    print(f"WARNING: could not parse JSON patch from: {text[:200]}")
    return {}
```

---

## Step 6 — Terminate cleanly

The loop ends when `state["done"] == True`. The agent sets this in its patch when the objective is complete.

After the loop exits, output the final state as the result:

```python
if state["done"]:
    print("Completed. Final state:")
    print(json.dumps(state, indent=2))
else:
    print(f"Hit MAX_STEPS ({MAX_STEPS}) without completing. Final state:")
    print(json.dumps(state, indent=2))
    # Decide: retry from current state, or escalate to user
```

---

## What "working" looks like

When this skill is applied correctly:

1. **Schema defined first** — the agent outputs the JSON schema before any tool call, with field names and types explained.
2. **Each step prompt contains only** `SKILL_SPEC + CURRENT_STATE + LATEST_OBSERVATION` — no prior tool outputs, no prior reasoning.
3. **Reasoning is used then discarded** — chain-of-thought produces the patch, then is dropped. It never appears in the next step.
4. **Patches are validated** before applying — unknown fields, empty patches, and type errors are caught.
5. **State stays compact** — at step 30 the state JSON is the same size as at step 1. If it's growing, something is wrong.

---

## Common mistakes

**Pasting prior observations into the prompt.** If you find yourself including tool outputs from previous steps — stop. Either commit that data to state, or it doesn't need to persist.

**State growing unboundedly.** Arrays like `sources_checked` or `files_modified` should stay bounded. After ~20 items, collapse to a count or summarise: `"sources_checked": "12 sources checked, see key_findings"`.

**Schema designed mid-task.** Define the schema before step 1 runs. Changing schema mid-loop forces a state migration and usually breaks things.

**Skipping validation.** Without patch validation, one malformed model output silently corrupts state and every subsequent step is wrong.

**Using this for tasks under 10 steps.** The schema design overhead isn't worth it. Just use standard Hermes tool calls.

---

## Source

Paper: SKILL.state: Scalable Long-Horizon Agent Skills
Authors: Sanket Badhe, Priyanka Tiwari, Jonghyun Chung (Google LLC)
arXiv: https://arxiv.org/abs/2608.26263
License: CC BY 4.0