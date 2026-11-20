# DDEV-side notes

## Workaround branch (tested)

[`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid)
(one commit, `794c0a4ae`, on DDEV main `571f19aee`; no PR yet) makes DDEV
work on Kiri releases without either Kiri fix:

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

## Provider detection

`docker info` on Kiri reports `OperatingSystem: Kiri`, `Name: kiri`, and
`Runtimes: kiri`. `docker version` reports `Platform.Name: Kiri` and a `Kiri`
component with Kiri's own version (the Engine version is reported as 27.5.1,
API 1.47). DDEV's provider checks in `pkg/dockerutil/providers.go`
(`IsDockerDesktop`, `IsOrbStack`, `IsColima`, …) don't match, so Kiri is
handled as generic Docker. An `IsKiri()` along the same lines is easy, if
something needs it, for example `ddev version`/`ddev debug test` output or
provider-specific advice.

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
