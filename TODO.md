# Next steps with Kiri

## Waiting on upstream

- [ ] **libracoder/kiri#595** (ownership fix): answer review comments, and sign
      the CLA if CLA Assistant asks. Its checklist has two unticked boxes:
  - "works on macOS, Windows and Linux": tick it once the macOS run (below)
    posts its "For libracoder/kiri#595" summary as a PR comment. Windows stays
    untested unless someone runs it under WSL2.
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

- [ ] Run the macOS evaluation: hand [docs/macos-agent-prompt.md](docs/macos-agent-prompt.md)
      to an agent on a Mac with push access to this repository. Review
      `results/macos-*.md` before anything is posted upstream.
- [ ] Try Kiri installed normally on Linux (`.deb` with systemd, not nested),
      where only #594 should matter. The `host.docker.internal` check is a
      real test there.
- [ ] Windows/WSL2: not planned yet.
