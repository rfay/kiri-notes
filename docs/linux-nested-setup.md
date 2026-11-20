# Linux: Kiri nested on an existing Docker daemon (what was tested)

The machine was a Coder workspace (Ubuntu, kernel 6.8, x86-64) whose Docker
daemon (29.9.3) runs inside a user namespace (`/proc/self/uid_map` is
`0 165536 65536`). That daemon is shared with other work, so Kiri had to stay
out of its way: no host ports, no changes to the host's firewall rules, no
changes to the default docker context.

## Approach

Kiri's own Linux test (`tests/linux-host.sh`) runs the engine inside a
privileged container on an existing Docker engine. This setup does the same:

- The engine container has its own network namespace. Kiri's bridges, NAT
  rules and published ports stay inside it, and nothing binds the host's ports.
  Ports Kiri publishes are reached on the engine container's IP (here `172.17.0.2`).
- The engine's socket is bind-mounted out to `<work dir>/run/docker.sock`, and a
  docker context points at it.
- `<work dir>` is mounted at the same path inside, so DDEV's bind mounts of
  project directories under it resolve. So are the mkcert CAROOT (read-only)
  and the SSH agent socket's directory, for `ddev-ssh-agent`.
- DDEV runs with its own global config (`DDEV_XDG_CONFIG_HOME`) using alternate
  router ports. Kiri itself listens on 443 inside its namespace for its
  `*.kiri.localhost` HTTPS, so the router can't use 443 there anyway.

## Steps

1. **Get Kiri's source with the fixes.** Both branches are needed here: #2
   and #3 make it work nested at all, and #1 makes DDEV work.

   ```bash
   git clone https://github.com/rfay/kiri ~/kiri-test/kiri
   cd ~/kiri-test/kiri && git checkout -b ddev-test origin/20261119_rfay_userns_devices && git cherry-pick origin/20261119_rfay_archive_keep_owners
   ```

   The released `.deb` (0.2.2) has static binaries in `usr/bin/` (`dpkg-deb -x`),
   but in this environment they can't start any container (problem 2).

2. **Build the engine** (about 2.5 minutes the first time, about 25 s after a change):

   ```bash
   scripts/build-kiri-linux.sh ~/kiri-test/kiri ~/kiri-test/bin
   ```

3. **Start it and create the context** (prints the engine's IP):

   ```bash
   scripts/run-kiri-engine.sh ~/kiri-test/bin ~/kiri-test kiri-engine
   docker --context kiri-engine run --rm alpine echo hello
   ```

4. **Give DDEV its own global config with alternate ports**, seeded from your normal one:

   ```bash
   export DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config DOCKER_CONTEXT=kiri-engine
   mkdir -p $DDEV_XDG_CONFIG_HOME/ddev && cp ~/.ddev/global_config.yaml $DDEV_XDG_CONFIG_HOME/ddev/
   ddev config global --router-http-port=28080 --router-https-port=28443 \
     --mailpit-http-port=28025 --mailpit-https-port=28026 --router-bind-all-interfaces=true \
     --instrumentation-opt-in=false
   ```

   `router_bind_all_interfaces` is needed because the router has to be reached
   on the engine container's IP, not on its localhost. XHGui (28142/28143) and
   the Traefik monitor port (20999) were moved too, to stay clear of other
   projects on the same Kiri.

5. **Run the smoke test:**

   ```bash
   ROUTER_IP=172.17.0.2 scripts/ddev-smoke-test.sh ~/kiri-test/proj/smoke
   ```

   DDEV warns that `nothing answers on host port(s) …`. That's expected,
   because it checks the workspace's localhost while the ports are on the
   engine's IP.

## Results (patched Kiri at d80976c, DDEV v1.25.5-87, PHP project)

```text
PASS ddev start (21s)                     PASS snapshot
PASS http via router :28080               PASS snapshot restore
PASS https via router :28443 (mkcert CA)  PASS data back after restore
PASS ddev exec                            PASS export-db
PASS web runs as host uid                 PASS composer
PASS bind mount: host file visible        PASS mailpit
PASS bind mount: container file owned by host user
PASS mysql                                PASS host.docker.internal resolves
FAIL web container reaches host via host.docker.internal
PASS ddev restart (13s)                   PASS http after restart
SUMMARY pass=17 fail=1
```

The failure comes from the nesting. `host.docker.internal` resolves to the
project network's gateway (`172.19.0.1`), which is inside Kiri's network
namespace, so it's the engine container rather than the workspace, and a
server on the workspace isn't reachable there. On a normal Linux install and
on a Mac this is the real test of Xdebug connectivity.

Also checked by hand: the first `ddev start` builds images through Kiri's
BuildKit (`buildx_buildkit_default`, a privileged container that Kiri runs),
about 35 s cold and under 5 s cached. A stop/start cycle took about 12 s.
`ddev-ssh-agent` relays to the mounted agent socket.

## Two projects at once

Starting a second project while the first runs fails with released DDEV,
because Kiri refuses to disconnect the running router from `ddev_default`
(problem 5 in [kiri-fixes.md](kiri-fixes.md)). With DDEV built from
[`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid),
the router is recreated instead. Two projects then ran at once, with 17 of 18
checks passing on each, on a Kiri **without** the ownership fix:

```bash
PATH=<ddev checkout>/.gotmp/bin/linux_amd64:$PATH ROUTER_IP=172.17.0.3 scripts/ddev-smoke-test.sh ~/kiri-test/proj/wa wa
PATH=<ddev checkout>/.gotmp/bin/linux_amd64:$PATH ROUTER_IP=172.17.0.3 scripts/ddev-smoke-test.sh ~/kiri-test/proj/wb wb
```

## Cleanup

```bash
DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config DOCKER_CONTEXT=kiri-engine ddev delete -Oy kirismoke
```

```bash
docker context rm kiri-engine && docker stop kiri-engine && docker container rm kiri-engine
```

```bash
docker volume rm kiri-engine-data kiri-engine-home kiri-cargo-registry
```
