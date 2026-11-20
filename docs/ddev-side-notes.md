# DDEV-side notes

Nothing in DDEV has been changed for Kiri. These are candidates, not decisions.

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

## A possible DDEV workaround for the copy-in ownership bug (unverified)

Until a Kiri release includes [#595](https://github.com/libracoder/kiri/pull/595),
DDEV could pass `CopyUIDGID: true` in `dockerutil.CopyArchiveToContainer`
(`client.CopyToContainerOptions`) for the CA copy:

- Kiri keeps the archive's owners when `copyUIDGID` is set, which is what DDEV wants.
- Docker then gives the files to the container's user. The web container's user is the
  host uid:gid, the same owner DDEV writes into the tar, so the result should be the same.

This hasn't been tried on Docker, Podman or other providers, and
`copyUIDGID` behaviour varies by engine, so it's only worth doing if Kiri
users show up before #595 ships.

## Router ports on a Mac

Kiri's Mac app claims host ports 80 and 443 for `http(s)://<name>.kiri.local`
routing when that feature is on. (Kiri's own e2e notes say "there is one pair
of ports 80 and 443 on a Mac, and the installed Kiri has them".) DDEV's router
wants the same ports by default. Either turn Kiri's domains off (Settings →
Domains), or give DDEV other router ports. DDEV's port-conflict message could
mention Kiri the way it mentions other tools.
