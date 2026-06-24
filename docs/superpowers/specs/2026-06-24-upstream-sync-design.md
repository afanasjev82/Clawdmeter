# Design: keep the M5Stack fork private, sync upstream periodically

**Date:** 2026-06-24
**Status:** Approved; first sync executed 2026-06-24.
**Branches:** `m5stack-core` (our work), `main` (upstream mirror)
**Remotes:** `origin` = `afanasjev82/Clawdmeter` (fork), `upstream` = `HermannBjorgvin/Clawdmeter`

## Decision

Keep our M5Stack Core support in the **private fork** and **periodically merge upstream
changes in**, rather than contributing the work back upstream via PRs.

A repeatable procedure for this lives in the `upstream-sync` skill
(`.claude/skills/upstream-sync/SKILL.md`). This document is the rationale + the
canonical description of the topology the skill assumes.

### Why not upstream?

The work was analysed (diff `main`..`m5stack-core`, 38 files) and sorts into four tiers:

| Tier | What | Upstream fit |
|---|---|---|
| 1. Board-isolated | `boards/m5stack_core/*`, `platformio.ini` env | clean |
| 2. Small enablers the board requires | `has_touch` cap, touchless splash-toggle, 320×240 responsive breakpoint | additive |
| 3. Generally-useful features | configurable screen sleep, USB-serial transport, BLE `rx_buf` race fix | separable |
| 4. Deployment-specific | Docker stack + serial daemon + token refresher + `.env` | **private** |

A strict "boards-only PR" is **not** possible (the board genuinely needs Tier 2),
but Tiers 1–3 *are* upstream-friendly. We chose to stay private anyway, for control
and to avoid PR-negotiation overhead. Tier 4 stays private regardless of that choice.

## Topology

- **`main` is a pristine mirror of `upstream/main`.** We never commit to it. This makes
  pulling upstream a trivial fast-forward that can never conflict. (We had to repair a
  stray commit on `origin/main` — `42ad2c4` — to restore this invariant; see History.)
- **`m5stack-core` = `main` + all our work (Tiers 1–4) + docs + this skill.** Everything
  lives and deploys from here.

```text
upstream/main ──ff──▶ main ──merge──▶ m5stack-core ──▶ crazybot deployment
 (HermannBjorgvin)   (mirror)         (mirror + our 32 commits)
```

## Sync procedure (encoded in the skill)

1. `git fetch upstream && git fetch origin`. Record `PRE=$(git rev-parse m5stack-core)`.
2. Fast-forward the mirror: move `main` to `upstream/main`, push to `origin`.
3. `git checkout m5stack-core && git merge --no-edit main`.
4. Resolve conflicts. **`daemon/` is the hot zone** — upstream is most active there and we
   have private daemon code. Firmware conflict risk is low (upstream rarely touches the
   shared firmware or our board).
5. Verify (below). 6. Push `m5stack-core`. Rollback: `git merge --abort` (pre-commit) or
   `git reset --hard $PRE` (post-commit, pre-push).

## Verification policy (path-aware)

- **Always:** `pio run -d firmware -e m5stack_core` — catches merge-induced compile breaks.
- **If the merge changed `firmware/src/` (shared or the m5stack board) or the m5stack env
  in `platformio.ini`:** flash crazybot and run the serial sanity check (`[boot]
  reset_reason`, `OK sleep`, `ACK`). Otherwise the m5stack binary is unchanged → **no reflash**.
- **If it changed any daemon file bundled in the crazybot Docker image** (`claude_usage_daemon.py`,
  `claude_usage_daemon_serial.py`, `token_refresher.py`, `Dockerfile`, `docker-compose.yml`,
  `requirements-docker.txt`): **redeploy to crazybot** so its running code equals the repo — even
  when the change looks behaviorally irrelevant to the serial path (keep-current policy). First
  confirm `claude_usage_daemon_serial.py`'s imports from `claude_usage_daemon.py` (`read_token`,
  `poll_api`, `log`, `POLL_INTERVAL`) still resolve; after redeploy check `docker logs
  clawdmeter-daemon-serial` for `[dev]` + `ACK`.

## Conflict-minimization principle (ongoing)

Keep upstream-owned files unedited where possible; put M5Stack / deployment knowledge in
**new** files upstream lacks (the board folder, `docs/`, `.claude/`). We already do this:
`CLAUDE.md` is byte-identical to upstream, so it never conflicts. Prefer documenting the
M5Stack port in a separate `docs/` file over editing upstream's `CLAUDE.md`.

## History — first sync (2026-06-24)

- Repaired `origin/main`: a stray `chore: add .gitignore` commit (`42ad2c4`) had been
  committed on top of `upstream/main`. Removed via `git push origin main --force-with-lease`
  (local `main` was already clean at `upstream/main`). Nothing lost — `m5stack-core` carries
  its own identical `firmware/.gitignore`.
- Merged 11 upstream commits → **one** conflict, in `daemon/claude_usage_daemon_windows.py`:
  both sides had independently set `DEVICE_NAME = "Clawdmeter"`. Kept our commented version.
- All 11 upstream commits were BLE/Windows/macOS-daemon or C6-board work — **zero** functional
  impact on the M5Stack firmware or our serial path. Firmware rebuilt clean; no reflash. We still
  **redeployed the merged daemon to crazybot** (`claude_usage_daemon.py` is bundled in the image)
  per the keep-current policy — verified healthy (`[dev] {"ready":true}`, `OK sleep=30`, `ACK`).
- Result: `main` = `upstream/main` = `52b23c8`; `m5stack-core` pushed, 0 behind upstream.
