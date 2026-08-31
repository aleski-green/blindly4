# Questions & Ideas

Open questions, feature ideas, and architectural considerations discovered during testing.

---

## Q1: Can agents parallelize blindy work?

**Context:** During testing, all tests ran sequentially because blindy controls a single shared desktop — two agents clicking/typing simultaneously would interfere.

**Short answer:** True parallelism is impossible (one desktop, one focus, global keystrokes).

**Idea — async cooperative switching:**

Instead of parallel execution, agents could use a **cooperative async model** (similar to Python's asyncio, not threading):

- **Agent A** uses blindy to navigate Telegram, then yields control while it processes the AX tree data, generates code, or writes a report.
- **Agent B** picks up blindy access, runs its Finder test, then yields.
- Agents take turns holding the "blindy lock" — only one interacts with the desktop at a time.

This is analogous to:
```
async def test_telegram(blindy_lock):
    async with blindy_lock:
        # UI interaction phase — exclusive access
        await blindy.activate(pid=56688)
        tree = await blindy.show(depth=5)
    
    # Processing phase — no lock needed, other agents can use blindy
    report = analyze(tree)
    write_report(report)
    
    async with blindy_lock:
        # Back to UI for the next step
        await blindy.click(x=800, y=948)
```

**Benefits:**
- Better utilization of wait time (while one agent analyzes data, another uses the desktop)
- Reports and code generation happen in parallel
- Only the actual `blindy` calls are serialized

**Open questions:**
- How to implement the "lock" — is it a file lock, a service-level mutex, or orchestrator-managed?
- How to handle state handoff — Agent B might change the desktop state that Agent A expects
- Should blindy itself support a queue/scheduler for commands?
- Could the blindy service act as the coordinator, queuing commands from multiple clients?

**Status:** Idea — needs design discussion with blindly developers.

---

## Q2: Service vs --no-service permission deadlock

**Context:** The blindy service process runs as a separate daemon (PPID 1) and doesn't inherit the terminal's Accessibility permission. This forces `--no-service` mode, which breaks `snapshot`/`changes`.

**Question:** How should Accessibility permission be granted to the service process?

**Options:**
1. Service inherits permission from the launching terminal (requires service restart from permitted terminal)
2. Grant permission directly to the `blindy` binary in System Settings
3. Service runs within the terminal process (not as a daemon)

**Status:** Blocking issue for `snapshot`/`changes` functionality.

---

## Q3: Desktop element interaction reliability

**Context:** Across both tests, interacting with UI elements through AX paths was unreliable:
- Paths change between reads
- `show-menu` fails on some elements (Finder Desktop)
- `type` doesn't always land in focused fields
- `focused` command often returns "no focused element"

**Question:** Is there a more reliable targeting mechanism than index-based paths? Could blindy support:
- Targeting by AX identifier (stable across reads)?
- Targeting by coordinates (already supported via `click`)?
- A "find and act" atomic operation (find + press in one call)?

**Status:** Design question for blindy developers.
