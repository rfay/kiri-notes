# Next steps with Kiri

## Waiting on upstream

- [ ] **libracoder/kiri#595** (ownership fix): answer review comments, and sign
      the CLA if CLA Assistant asks. Its checklist has two unticked boxes:
  - "works on macOS, Windows and Linux": the macOS run is done and passed
    ([results/macos-20261120-arm64.md](results/macos-20261120-arm64.md)).
    Next: post its "For libracoder/kiri#595" section as a PR comment from your
    own `gh`, then tick the box for macOS. Windows stays untested unless
    someone runs it under WSL2.
  - "`cargo fmt`, `cargo clippy` and the tests pass": they report the same
    findings on main as on the branch (the repo has no fmt/clippy config). The
    PR body explains this; leave the box as it is unless a maintainer asks.
- [ ] **libracoder/kiri#597** (engine in a user namespace): wait for the
      maintainers to agree on an approach. Then open a PR from
      [`rfay/kiri:20261119_rfay_userns_devices`](https://github.com/rfay/kiri/tree/20261119_rfay_userns_devices),
      adding a `tests/linux-host.sh` case if they want one.

## Problem 5: a running container can't leave its first network (not filed yet)

Kiri refuses `POST /networks/{id}/disconnect` for a running container's first
network (409, "Kiri cannot disconnect a running container from its first
network"). Docker allows it. So DDEV can't update the running router's
aliases, and a second project can't start while another runs. Details:
[docs/kiri-fixes.md](docs/kiri-fixes.md#5-running-container-cant-leave-its-first-network-breaks-a-second-project).

On macOS with released DDEV (2026-11-20) it bites even with a single
project: the router outlives stopped projects, so starting any project other
than the one the router was created for fails until the router is removed
(`ddev poweroff`). Kiri 0.2.2's message is shorter: "Kiri cannot disconnect a
container from its first network (ddev_default)". Put both in the issue.

Plan for the upstream issue, once the maintainers have responded to #594, #595 and #597:

- [ ] Rebuild a Kiri engine with `scripts/build-kiri-linux.sh` and
      `scripts/run-kiri-engine.sh` (the earlier engines were cleaned up).
- [ ] Capture a plain `docker` CLI reproduction on both Docker and Kiri, with
      real output: run a container on a user network, `docker network disconnect`
      it while it runs, then `docker network connect --alias <name>` it again.
      Docker should succeed and Kiri return 409. That hasn't been run as a
      standalone repro yet; it was seen through DDEV.
- [ ] File it with Kiri's bug form. Lead with the CLI repro, then the DDEV
      context (`pkg/ddevapp/router.go`, `dockerutil.UpdateContainerNetworkAliases`).
      Reference #418/#584 and the comment in `crates/kiri/src/daemon/engine.rs`
      (`disconnect`) that explains why it's refused. Suggest the narrow case:
      an immediate reconnect of the same container to the same network, which is
      DDEV's pattern, or changing aliases without a disconnect. Say that DDEV has a
      fallback, so it isn't urgent.
- [ ] Post it from your own shell with `gh issue create --repo libracoder/kiri …`
      (this repo's Claude sessions can't post to libracoder/kiri).

## macOS: the Finder mount hangs (not filed yet)

What this is: Kiri shows every container's files in Finder. The engine runs a
small NFS server on a Unix socket (`~/.kiri/files/nfs.sock`) and mounts it
read-only at `~/Kiri` (`~/Kiri Ddev` for the dev build), with one folder per
container (`~/Kiri/<container>/etc/…`). It has nothing to do with DDEV's
project files, which use virtiofs bind mounts or Mutagen. DDEV never touches
`~/Kiri`.

What happened on 2026-11-20 (engines started with `kiri daemon` from a
terminal, not by opening the app):

- `mount` showed both mounts, but `ls ~/Kiri` and `ls ~/"Kiri Ddev"` hung
  on every attempt, including right after a clean restart of the dev engine
  (a fresh mount).
- Kiri's e2e suite stalled in its "container files in Finder" section: a
  `shasum` of a file under the mount stayed stuck in the kernel, and the run
  never finished.
- Stopping the engine (SIGTERM) logged `engine shutting down signal=15`, but it
  kept serving requests: shutdown runs `umount -f ~/Kiri Ddev`, which waited on
  that stuck process. Killing the process let the shutdown finish.

Why it matters: DDEV works without it. But anything that walks the home
folder (Finder, Spotlight, backups, `find ~`) can hang on a dead `~/Kiri`,
and a stuck reader stops Kiri from quitting.

Before filing:

- [ ] Reproduce with the app opened normally (`open -a Kiri`), not
      `kiri daemon`, on a Mac where someone can answer prompts. If it works
      there, the cause may be how the engine was started (or a macOS prompt
      nobody could answer), and it may not be a Kiri bug.
- [ ] If it still hangs, collect `kiri diag logs --engine`, `mount | grep Kiri`,
      and whether `~/.kiri/files/nfs.sock` accepts a connection.
- [ ] File it with Kiri's bug form, from your own `gh`.

## macOS: notes that don't need action

- Kiri logs `the VM's NAT network is still unreachable; published ports keep
  going over vsock … No route to host (os error 65)` on an unattended Mac. It's
  macOS Local Network privacy, as with Apple's container runtime on the
  testbots. Kiri falls back to vsock and published ports work. Worth one
  sentence in the Finder or problem 5 issue only if a maintainer asks about
  the environment.

## DDEV

- [ ] Decide whether to propose
      [`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid)
      to ddev/ddev. Before that:
  - run it on Podman (rootless with keep-id, and rootful), Colima, OrbStack,
    Rancher Desktop and Docker Desktop. `copyUIDGID` handling is the main unknown;
  - run the relevant DDEV tests (router and start tests) with the
    workspace-wide Docker lock;
  - if Kiri ships #595 and a fix for problem 5 first, the branch may only be
    worth keeping for the router fallback, or not at all.
- [ ] Consider `IsKiri()` in `pkg/dockerutil/providers.go` (`OperatingSystem: Kiri`),
      for `ddev debug test` output and provider-specific advice such as Kiri's
      Mac app holding ports 80/443 ([docs/ddev-side-notes.md](docs/ddev-side-notes.md)).

## Testing

- [x] Run the macOS evaluation (2026-11-20, M1, macOS 27.2.1):
      [results/macos-20261120-arm64.md](results/macos-20261120-arm64.md).
      Released Kiri with released DDEV works one project at a time; the DDEV
      workaround branch works with two; #595 passes. Review the results file
      before posting its #595 section.
- [ ] Optionally repeat on a Mac where the Kiri app can be opened normally,
      to settle the Finder hang and to test DDEV's default ports (80/443) with
      Kiri's domains off.
- [ ] Try Kiri installed normally on Linux (`.deb` with systemd, not nested),
      where only #594 should matter. The `host.docker.internal` check is a
      real test there.
- [ ] Windows/WSL2: not planned yet.
