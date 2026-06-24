---
name: upstream-sync
description: Use when syncing this private Clawdmeter fork with the upstream repo (HermannBjorgvin/Clawdmeter) — "sync upstream", "pull upstream changes", "merge upstream into m5stack-core", "catch up with the original repo". Keeps `main` a pristine upstream mirror and merges it into `m5stack-core` with conflict-resolution and verification gates.
---

# Sync the private fork with upstream

This fork keeps M5Stack Core support private and periodically merges upstream in
(decision + rationale: `docs/superpowers/specs/2026-06-24-upstream-sync-design.md`).

## Invariants (do not break)

- **`origin` = `afanasjev82/Clawdmeter` (fork); `upstream` = `HermannBjorgvin/Clawdmeter`.**
- **`main` is a pristine mirror of `upstream/main`. NEVER commit to `main`.** All our work
  lives on `m5stack-core`. If `main` ever drifts (a stray commit on `origin/main`), repair it
  before syncing — see "Repair a drifted main".
- Mental model: you only check out the *local* branches `main` and `m5stack-core`. `origin/*`
  and `upstream/*` are remote-tracking refs you `fetch` and `merge`/`diff` against — you do not
  check them out. `git checkout --track origin/main` FAILS when local `main` exists; just use
  `git switch main`.

## Procedure

Run from the repo root. Substitute the device/host specifics under "Deployment" below.

```bash
# 1. Fetch both remotes; record a rollback point
git fetch upstream && git fetch origin
PRE=$(git rev-parse m5stack-core)          # rollback target

# 2. Get onto our branch first, so step 3 can move `main` without checking it out
#    (git branch -f FAILS on a branch that is currently checked out)
git switch m5stack-core

# 3. Fast-forward the mirror (main) to upstream, publish it
git branch -f main upstream/main           # move main without checkout (keeps your worktree)
git push origin main --force-with-lease    # only "forces" if main had drifted; else a plain update

# 4. Merge the mirror into our branch
git merge --no-edit main
```

If step 4 reports conflicts, resolve them (see "Conflicts"), `git add` each, then
`git commit --no-edit`. If it merges cleanly it auto-commits.

```bash
# 5. What did the merge actually touch? (drives verification)
git diff --stat $PRE HEAD -- firmware/src firmware/platformio.ini   # firmware impact
git diff --stat $PRE HEAD -- daemon                                  # daemon impact
```

## Conflicts

**`daemon/` is the hot zone** — upstream is most active there and we carry private daemon
code. Firmware conflicts are rare (upstream rarely touches shared firmware or our board).

- Our private daemon files (`claude_usage_daemon_serial.py`, Docker stack, `token_refresher.py`)
  are *new* files upstream lacks → they should not conflict.
- Overlap files to watch: `claude_usage_daemon_windows.py`, `claude_usage_daemon.py`. When both
  sides made the *same* change (it happens — e.g. both renamed `DEVICE_NAME` to `"Clawdmeter"`),
  keep ours.
- After resolving, confirm none remain: `grep -rn '^<<<<<<<\|^>>>>>>>' firmware daemon`.

## Verification gates (run only what applies)

- **Always:** `pio run -d firmware -e m5stack_core` — catches merge-induced compile breaks.
- **If the merge changed `firmware/src/` (shared or `boards/m5stack_core/`) or the
  `[env:m5stack_core]` section of `platformio.ini`:** the binary changed → flash + serial sanity
  (see Deployment). If it only touched another board (e.g. `boards/waveshare_*`) or a comment,
  the m5stack binary is unchanged → **no reflash**.
- **If the merge changed `daemon/`:** confirm the serial daemon's imports still resolve, then
  redeploy and check logs:
  ```bash
  for s in "def read_token" "def poll_api" "def log" "POLL_INTERVAL ="; do grep -q "$s" daemon/claude_usage_daemon.py || echo "MISSING: $s"; done
  ```

## Finish

```bash
git push origin m5stack-core
git rev-list --left-right --count main...m5stack-core   # expect "0  <N>" (0 behind upstream)
```

## Rollback

- Mid-merge (before commit): `git merge --abort`.
- After the merge commit, before push: `git reset --hard $PRE`.

## Repair a drifted main

If `origin/main` has commits not in `upstream/main` (someone committed to it, e.g. via the
GitHub UI), restore the mirror — nothing is lost as long as the content also lives on
`m5stack-core`:

```bash
git fetch upstream && git fetch origin
git branch -f main upstream/main
git push origin main --force-with-lease
```

## Gotchas seen in practice

- Switching to `main` can fail with "untracked working tree files would be overwritten by
  checkout: firmware/.gitignore". That file is tracked only on `m5stack-core`; `rm -f
  firmware/.gitignore` then switch — it's restored from the branch you land on.
- Don't confuse "1 commit ahead of upstream" on GitHub with being behind — a stray commit on
  `origin/main` shows as ahead. Repair as above.

## Deployment (our current host: crazybot, USB-serial + Docker)

Only needed when a verification gate above says so. The M5Stack stays plugged into crazybot.

```bash
# build + ship firmware (only if the m5stack binary changed)
pio run -d firmware -e m5stack_core
scp firmware/.pio/build/m5stack_core/firmware.bin afanasjev@crazybot:/tmp/firmware.bin
ssh afanasjev@crazybot 'cd ~/Clawdmeter/daemon && ./stop.sh && \
  ~/.local/bin/esptool.py --chip esp32 \
    --port /dev/serial/by-id/usb-Silicon_Labs_CP2104_USB_to_UART_Bridge_Controller_017059CD-if00-port0 \
    --baud 460800 write_flash 0x10000 /tmp/firmware.bin && \
  cd ~/Clawdmeter/daemon && ./start.sh -t usb -d'

# serial sanity (expect [boot] reset_reason, OK sleep, ACK, [dev]-prefixed lines)
ssh afanasjev@crazybot 'docker logs --since 30s clawdmeter-daemon-serial'
```

To deploy *merged daemon* code to crazybot, update its checkout (`cd ~/Clawdmeter && git fetch
origin && git checkout m5stack-core && git reset --hard origin/m5stack-core`) — but preserve its
local `daemon/.env` (e.g. `SCREEN_SLEEP_SECONDS`), which is gitignored and host-specific — then
`./start.sh -t usb -d`. Skip this when the merge brought no functional change for the
serial/Docker path (as in the 2026-06-24 sync, where upstream's commits were all BLE/Windows/
macOS-daemon or C6-board work).
