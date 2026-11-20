# Kiri as a Docker provider for DDEV

Notes from evaluating [Kiri](https://github.com/libracoder/kiri) as a Docker
provider for [DDEV](https://github.com/ddev/ddev).

Kiri is a small container runtime written in Rust. It serves the Docker
Engine API without dockerd, containerd or runc, so the `docker` CLI, Compose
and buildx work against it. On macOS and Windows it runs one small Linux VM.
On Linux it starts containers directly on the host kernel. It installs a
`kiri` docker context. Kiri reports `OperatingSystem: Kiri`, so DDEV treats it
as generic Docker, with no provider-specific handling.

## Status (2026-11-20)

| Platform | Kiri | Result |
|---|---|---|
| Linux, Kiri engine nested in a privileged container on a user-namespaced Docker (a Coder workspace) | 0.2.2 / main d80976c **with 3 patches** | One project works: 17 of 18 smoke checks pass, and the one failure comes from the nesting (see [docs/linux-nested-setup.md](docs/linux-nested-setup.md)). A **second** project fails to start while the router runs (problem 5) unless DDEV has the workaround branch |
| Same, Kiri **without** the ownership fix, DDEV from [`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid) | d80976c with only the user-namespace patches | Two projects at once, 17 of 18 checks each (same nesting-only failure) |
| Linux, Kiri installed normally (`.deb`, systemd) | not tried | expected to need only the ownership fix (#595) |
| macOS (Apple silicon / Intel) | not tried | plan in [docs/macos-testing-plan.md](docs/macos-testing-plan.md) |
| Windows / WSL2 | not tried | |

With released Kiri and released DDEV, **`ddev start` fails on every platform**:
the web container exits with
`ERROR: failed to read the CA key: open /usr/local/lib/ddev/mkcert/rootCA-key.pem: permission denied`.
Even with that fixed, a second project can't start while another is running.
Either both Kiri fixes are needed, or the DDEV branch, which works around both;
see [docs/ddev-side-notes.md](docs/ddev-side-notes.md). Details are in
[docs/kiri-fixes.md](docs/kiri-fixes.md).

## What has to be fixed in Kiri

| | Problem | Affects | Upstream | Fix |
|---|---|---|---|---|
| 1 | `PUT /containers/{id}/archive` (docker cp) makes root the owner of every file; Docker keeps the tar's uid/gid | **everyone**: DDEV's mkcert CA copy | [libracoder/kiri#594](https://github.com/libracoder/kiri/issues/594) | PR [libracoder/kiri#595](https://github.com/libracoder/kiri/pull/595) |
| 2 | `mknod` of `/dev/null` etc. refused in a user namespace; no bind-mount fallback | engine running nested or in a user namespace | [libracoder/kiri#597](https://github.com/libracoder/kiri/issues/597) | prototype branch [`rfay:20261119_rfay_userns_devices`](https://github.com/rfay/kiri/compare/main...rfay:kiri:20261119_rfay_userns_devices) |
| 3 | Default `nofile` of 1048576 above the engine's hard limit | same as 2 | #597 | same branch |
| 4 | ~~Restarting the engine container fails with `VM did not boot: File exists`~~ | was the test setup (no tmpfs on `/run`), not Kiri | none needed | `--tmpfs /run` in `run-kiri-engine.sh` |
| 5 | `POST /networks/{id}/disconnect` refused (409) for a running container's first network; Docker allows it | **everyone running more than one DDEV project**: DDEV updates the router's aliases by disconnect/reconnect | not reported yet (follow-on to libracoder/kiri#418) | DDEV falls back to recreating the router (DDEV branch) |

## Quick start (Linux, nested; what was actually tested)

See [docs/linux-nested-setup.md](docs/linux-nested-setup.md). In short:

```bash
git clone https://github.com/rfay/kiri && git -C kiri checkout 20261119_rfay_userns_devices
git -C kiri cherry-pick origin/20261119_rfay_archive_keep_owners   # or merge both branches
scripts/build-kiri-linux.sh kiri ~/kiri-test/bin
scripts/run-kiri-engine.sh ~/kiri-test/bin ~/kiri-test kiri-engine
export DOCKER_CONTEXT=kiri-engine DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
ROUTER_IP=<engine IP printed above> scripts/ddev-smoke-test.sh ~/kiri-test/proj/smoke
```

## Layout

- [TODO.md](TODO.md): next steps, including the not-yet-filed issue for problem 5
- [docs/lessons-learned.md](docs/lessons-learned.md): read this before testing. Known failures and what they mean, and Kiri and DDEV details that cost time
- [docs/kiri-fixes.md](docs/kiri-fixes.md): each problem, its cause in Kiri's code, the fix, and how it was verified
- [docs/linux-nested-setup.md](docs/linux-nested-setup.md): the Linux setup used, step by step, and results
- [docs/macos-testing-plan.md](docs/macos-testing-plan.md): instructions for a macOS agent to repeat the evaluation
- [docs/ddev-side-notes.md](docs/ddev-side-notes.md): the tested DDEV workaround branch, and what else DDEV might change or detect for Kiri
- [docs/macos-agent-prompt.md](docs/macos-agent-prompt.md): the prompt to hand a macOS agent
- `scripts/`
  - `build-kiri-linux.sh`: build Kiri's static Linux engine from a checkout, in a Rust container
  - `run-kiri-engine.sh` (with `engine-entrypoint.sh`): run that engine in a privileged container and create a docker context
  - `repro-archive-owners.sh`: the #594 reproduction; prints `1234 1235 600` / `key` when fixed
  - `ddev-smoke-test.sh`: PASS/FAIL checks of a DDEV project on the current docker context (any platform)
