#!/usr/bin/env python3
"""
Token measurement harness for loop-context-manager benchmark.
Reads per-session token counts from the Hermes state DB.

Usage:
    python3 token_measure.py <session_id> <label>
    python3 token_measure.py   # list recent sessions

The Hermes state DB stores aggregate token counts in session_model_usage.
Per-message token_count is always 0 on Bedrock (aggregate-only billing).
The meaningful comparison metrics are:
  - api_call_count       (number of model round-trips)
  - output_tokens        (tokens the model generated)
  - cache_read_tokens    (accumulated context the model paid to re-read)
  - estimated_cost_usd   (total cost)
"""
import sqlite3
import sys

DB = os.path.expanduser("~/.hermes/state.db")  # override with HERMES_DB env var
if os.environ.get("HERMES_DB"):
    DB = os.environ["HERMES_DB"]


def get_latest_sessions(limit=10):
    conn = sqlite3.connect(DB)
    rows = conn.execute(
        "SELECT id, workspace, started_at FROM sessions ORDER BY started_at DESC LIMIT ?",
        (limit,)
    ).fetchall()
    conn.close()
    return rows


def get_session_totals(session_id):
    conn = sqlite3.connect(DB)
    rows = conn.execute("""
        SELECT model, api_call_count, input_tokens, output_tokens,
               cache_read_tokens, estimated_cost_usd
        FROM session_model_usage
        WHERE session_id = ?
    """, (session_id,)).fetchall()
    conn.close()
    return rows


def get_message_count(session_id):
    conn = sqlite3.connect(DB)
    row = conn.execute(
        "SELECT COUNT(*) FROM messages WHERE session_id = ?", (session_id,)
    ).fetchone()
    conn.close()
    return row[0] if row else 0


def report(session_id, label):
    sep = "=" * 60
    print(f"\n{sep}")
    print(f"SESSION: {label}")
    print(f"ID:      {session_id}")
    print(sep)

    totals = get_session_totals(session_id)
    if not totals:
        print("No usage data found for this session ID.")
        return None

    for model, calls, inp, out, cache_r, cost in totals:
        inp = inp or 0
        out = out or 0
        cache_r = cache_r or 0
        calls = calls or 0
        print(f"Model:             {model}")
        print(f"API calls:         {calls:,}")
        print(f"Input tokens:      {inp:,}")
        print(f"Output tokens:     {out:,}")
        print(f"Cache read tokens: {cache_r:,}")
        print(f"Total messages:    {get_message_count(session_id):,}")
        if cost:
            print(f"Estimated cost:    ${cost:.4f}")

    if not totals:
        return None
    model, calls, inp, out, cache_r, cost = totals[0]
    return {"model": model, "calls": calls or 0, "input": inp or 0,
            "output": out or 0, "cache_read": cache_r or 0, "cost": cost or 0}


if __name__ == "__main__":
    if len(sys.argv) > 1:
        session_id = sys.argv[1]
        label = sys.argv[2] if len(sys.argv) > 2 else session_id
        report(session_id, label)
    else:
        print("Recent sessions:")
        for sid, ws, ts in get_latest_sessions(10):
            print(f"  {sid}  workspace={ws or '—'}")