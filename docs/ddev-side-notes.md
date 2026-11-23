# DDEV-side notes

## Workaround branch (tested)

[`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid),
now draft PR [ddev/ddev#9167](https://github.com/ddev/ddev/pull/9167) (first
commit 1fb3805 on main 85dcf05), makes DDEV work on Kiri releases without
either Kiri fix:

1. **CA copy with `copyUIDGID`** (`pkg/ddevapp/caroot.go`, new
   `dockerutil.CopyArchiveToContainerAsUser`). Kiri keeps the archive's owners
   when `copyUIDGID` is set, and Docker gives the files to the container's
   configured user. The web container's user is `$DDEV_UID:$DDEV_GID`, the same
   owner DDEV writes into the tar, so on Docker nothing changes.
2. **Router alias fallback** (`pkg/ddevapp/router.go`). If updating the
   running router's network aliases in place fails, the router is recreated,
   as before the in-place update was added.

Tested:

| Engine | Result |
|---|---|
| Kiri (nested Linux) without #595, old DDEV | web container exits: `failed to read the CA key` (control) |
| Kiri (nested Linux) without #595, this branch | two projects at once; smoke test 17/18 on each (the one failure is the nesting-only host check); the second start recreated the router |
| Docker 29.9.3, this branch, router already running for other projects | CA files `1000:1000` in web; both projects answer over HTTPS; router updated in place, not recreated (still the container from two days earlier) |

`golangci-lint` on `pkg/ddevapp` and `pkg/dockerutil` reports 0 issues. DDEV's
own test suite wasn't run (it needs the workspace-wide Docker lock and
`ddev poweroff`). Not tried with Podman, Colima, OrbStack, Rancher Desktop or
Docker Desktop.

On macOS with Homebrew Kiri 0.2.2 (2026-11-22,
[results](../results/macos-20261122-arm64-brew.md)): two projects at once,
18/18 smoke checks each, CA owned `505 20`, router recreated for the second
project. The PR's base fails with the CA error. DDEV's `testpkg` and
`testcmd` were run against Kiri; see the results file.

A second commit on the branch (2f098e9) adds:

3. **`dockerutil.IsKiri()` / `IsKiriMacOS()`**; `ddev version` reports
   `docker-platform kiri`, and `ddev utility port-diagnose` says "Kiri".
4. **A hint when the router can't bind 127.0.0.1:80/443 on Kiri/macOS**
   (`pkg/ddevapp/router.go`): use unprivileged router ports.
5. **Test skips** for the tests that need 80/443, on Kiri/macOS, next to the
   existing rootless-Podman-on-macOS skips.

A third commit fixes `TestConfigValidate`, which requested
`http://x.ddev.site/` (port 80) whatever the router port was; it fails on any
provider run with 8080/8443 (rootless Podman, socktainer, Kiri on macOS).

## Found by running DDEV's tests on Kiri, not Kiri problems

- **PostgreSQL 12–17 snapshot restore on macOS** (likely every provider,
  only checked on Kiri). The restore appends to
  `/etc/postgresql/conf.d/recovery.conf` as the container user
  (`$DDEV_UID:$DDEV_GID` = `505:20` on a Mac). The db image's build does
  `chgrp "$username" /etc/postgresql/conf.d`, but on macOS gid 20 already
  exists in the image (`dialout`), so `groupadd --gid 20 <user>` fails and the
  user's group becomes 1000. The container runs as gid 20, which isn't in
  group 1000, and Docker adds no supplementary groups when both uid and gid
  are given. Result: `bash: line 1: /etc/postgresql/conf.d/recovery.conf:
  Permission denied`, the db container exits, and `TestDdevAllDatabases`
  stops the whole `pkg/ddevapp` test binary (DDEV's failure path exits the
  process). DDEV's CI runs with `GOTEST_SHORT=16`, which skips that test, so
  it may never have run on a Mac. A possible fix: pass
  `-c restore_command=true` for PostgreSQL 12+ as well (it's been a server
  setting since 12; DDEV already does this for 18+), so nothing is written
  under `/etc`. Needs a check on Docker Desktop or OrbStack first.
- **`TestUtilityDiagnoseCmd/OutsideHomeDirectory`** only runs with
  `DDEV_TEST_OUTSIDE_HOME=true` (set on this runner), and then always fails:
  it creates the temp directory and then calls `fileutil.CopyDir`, which
  refuses an existing destination.
- **`DDEV_RUN_TEST_ANYWAY=true`** in the runner's environment overrides
  `GOTEST_SHORT`, so `GOTEST_SHORT=true` still ran the full suites.

## Provider detection

`docker info` on Kiri reports `OperatingSystem: Kiri`, `Name: kiri`, and
`Runtimes: kiri`. `docker version` reports `Platform.Name: Kiri` and a `Kiri`
component with Kiri's own version (the Engine version is reported as 27.5.1,
API 1.47). DDEV's provider checks in `pkg/dockerutil/providers.go`
(`IsDockerDesktop`, `IsOrbStack`, `IsColima`, …) don't match, so Kiri is
handled as generic Docker. `IsKiri()` and `IsKiriMacOS()` now exist on the PR branch
(2f098e9).

## host.docker.internal / Xdebug

`pkg/dockerutil/host_docker_internal.go` uses `host-gateway` in `extra_hosts`
on Linux and sets nothing on macOS (except for Colima, which gets a fixed IP),
relying on the engine's built-in name. Kiri claims both:
`host.docker.internal` is built in, and `host-gateway` maps to the default
bridge's gateway on Linux and `198.19.248.254` on a Mac. This needs checking on
a Mac and on a normal Linux install (the smoke test's host-reachability check).

## Before proposing the branch upstream

- Run it on the other providers DDEV supports. Podman's `copyUIDGID` handling
  is the main unknown, especially rootless with keep-id.
- Decide whether the router fallback is wanted generally. It's cheap: an engine
  that supports the in-place update never reaches it.

## Router ports on a Mac

Kiri's Mac app claims host ports 80 and 443 for `http(s)://<name>.kiri.local`
routing when that feature is on. (Kiri's own e2e notes say "there is one pair
of ports 80 and 443 on a Mac, and the installed Kiri has them".) DDEV's router
wants the same ports by default. Either turn Kiri's domains off (Settings →
Domains), or give DDEV other router ports. DDEV's port-conflict message could
mention Kiri the way it mentions other tools.

More important (found 2026-11-22): **Kiri on macOS can't publish any port
below 1024 on 127.0.0.1 at all**, domains or not, because its engine runs as
the user and macOS allows unprivileged low ports only on the wildcard address
(details in the [results](../results/macos-20261122-arm64-brew.md#why-000080-works-and-12700180-doesnt)).
So on a Mac, Kiri needs `ddev config global --router-http-port=8080
--router-https-port=8443`, like rootless Podman and socktainer. DDEV's CI
already does that for those two (`.buildkite/test.sh`); a Kiri job would need
the same. Remember that the router publishes the ports of *every* running
project, so one project with 80/443 makes the router fail for all of them.
