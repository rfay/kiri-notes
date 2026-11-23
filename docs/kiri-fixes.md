# What has to be fixed in Kiri for DDEV

Code references are to `libracoder/kiri` main at `d80976c` (Kiri 0.2.2 plus a few commits).

## 1. Copy-in drops the archive's owners: breaks DDEV everywhere

- Upstream: issue [libracoder/kiri#594](https://github.com/libracoder/kiri/issues/594), PR [libracoder/kiri#595](https://github.com/libracoder/kiri/pull/595) (closed unmerged).
  **Fixed on Kiri main by #772** on 2026-11-23: it carries #595 (Randy kept
  as co-author) and adds Docker's `copyUIDGID` / `Config.User` behavior. The
  maintainer says it's for 0.2.3.
- Branch: [`rfay/kiri:20261119_rfay_archive_keep_owners`](https://github.com/rfay/kiri/tree/20261119_rfay_archive_keep_owners) (signed, one commit)

**Symptom in DDEV.** `ddev start` builds the images and starts the containers,
then the web container exits:

```text
+ mkcert -install
ERROR: failed to read the CA key: open /usr/local/lib/ddev/mkcert/rootCA-key.pem: permission denied
```

**Why.** DDEV puts the host's mkcert root CA into the web container with the
archive API (`PUT /containers/{id}/archive`). The tar entries belong to the
web user (the host uid/gid), and the key is mode 0600
([`pkg/ddevapp/caroot.go`](https://github.com/ddev/ddev/blob/main/pkg/ddevapp/caroot.go),
`caRootArchive` and `copyCAROOTIntoWeb`). Docker keeps the uid/gid from the
tar headers unless `copyUIDGID` is set; with it set, it gives the files to the
container's user instead (moby `containerExtractToDir`). Kiri's guest
unpacked with `set_preserve_ownerships(spec.flags & KEEP_OWNERS != 0)` in
`crates/kiri-init/src/linux/copy.rs`, so without `copyUIDGID` everything
became root's. A 0600 root-owned key can't be read by the web user.

The same applies to a plain `docker cp`. Docker Engine 29.9.3 keeps the host
file's uid/gid even without `-a`, and Kiri made them 0:0. Kiri's own e2e check
`cp-in-root-owner` asserted the wrong behaviour.

**Fix (PR #595).** Always keep the archive's owners on copy-in, update the
`KEEP_OWNERS` doc comment, and replace the e2e check with `cp-in-keeps-owner`
(a tar entry owned by 1234:1235, mode 0600, must keep its owner and be
readable by uid 1234). Kiri's internal copy-ins write uid 0 into their
headers, so they are unaffected.

**Verified** with `scripts/repro-archive-owners.sh`:

```text
== Kiri main (d80976c)        == Kiri with fix         == Docker Engine 29.9.3
0 0 600                       1234 1235 600            1234 1235 600
cat: ... Permission denied    key                      key
```

**Still different from Docker.** With `copyUIDGID` (`docker cp -a`), Docker
gives the files to the container's user; Kiri keeps the archive's owners.
DDEV doesn't set `copyUIDGID`, so this doesn't matter to it.

## 2. Device nodes in a user namespace: only when Kiri itself is nested

- Upstream: issue [libracoder/kiri#597](https://github.com/libracoder/kiri/issues/597) (waiting for the maintainers to agree before a PR)
- Branch: [`rfay/kiri:20261119_rfay_userns_devices`](https://github.com/rfay/kiri/tree/20261119_rfay_userns_devices) (signed prototype)

**Symptom.** Every container fails:
`kiri: cannot start container: mount: mknod dev/null: Operation not permitted (os error 1)`.
`--privileged` containers fail with `stdio: No such file or directory (os error 2)`,
and buildx's BuildKit container is privileged, so every `docker build` and
`ddev start` (which builds images) fails too.

**Why.** `mount_container_filesystems` in `crates/kiri-init/src/linux/container.rs`
creates `/dev/null`, `/dev/zero`, `/dev/full`, `/dev/random`, `/dev/urandom` and
`/dev/tty` with `mknod`, which the kernel refuses inside a user namespace. For
`--privileged`, `copy_host_devices` silently skips nodes it can't create, and
the standard nodes are then skipped as "already copied", so `/dev/null` is
missing.

**Fix (prototype).** On EPERM, bind-mount the host's node instead, as runc
does in a user namespace. For `--privileged`, create any standard node the
copy left out the same way.

## 3. Default open-file limit above the engine's own hard limit

Same issue (#597) and branch. `crates/kiri/src/daemon/hostopts.rs` gives every
container `nofile` 1048576:1048576 unless the run sets one. When the engine's
own hard limit is lower (524288 in the Coder workspace), `setrlimit` fails:
`ulimits: error setting rlimit type 7: operation not permitted`. The prototype
caps the default at the engine's hard limit (Linux only; the Mac daemon isn't
affected because the guest sets limits there).

Giving the engine container `--ulimit nofile=1048576:1048576` didn't help,
because the outer Docker can't exceed its own limit either.

## 4. Engine container restart: setup problem, not a Kiri bug

In the nested setup, `docker stop` and then `docker start` of the engine
container made `docker run` fail with `VM did not boot: File exists (os error 17)`,
sometimes for a run or two, sometimes until the container was recreated.

**Cause.** On Linux the daemon starts its agent with a private runtime
directory, `/run/kiri-agent-<daemon pid>-<n>` (`crates/kiri-vmm/src/process.rs`,
`runtime_directory`), and creates it exclusively, so an existing entry fails
the start instead of being trusted. A daemon that's killed leaves those
directories behind. The first engine container had a persistent `/run` (only
`/tmp` was a tmpfs), and inside a container the daemon often gets the same PID
(38 here) after a restart. So the new daemon tried to create a directory that
already existed. After a restart the engine container held
`/run/kiri-agent-38-0`, `-38-1`, `-38-2` and `-41-1`.

**Fix.** Mount a tmpfs on `/run`, as Kiri's own `tests/linux-host.sh` does.
`scripts/run-kiri-engine.sh` now does that, and three stop/start cycles in a
row then worked. The entrypoint also removes a stale socket before starting
the daemon. Before that, the `chmod` that opens the socket to the host user
could hit the old socket and leave the new one root-only.

On a normal host `/run` is cleared at boot, and a restarted daemon rarely gets
the same PID, so this is unlikely to affect normal installs. It only affects a
daemon that runs in a container with a persistent `/run`. Kiri could remove
its leftover `kiri-agent-*` directories when it starts, but this isn't worth
an upstream issue on its own.

## 5. Running container can't leave its first network: breaks a second project

- Upstream: not reported yet. libracoder/kiri#418 (fixed by #584) let a *stopped* container leave its first network; a running one is still refused.
- DDEV workaround: [`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid)

**Symptom.** The first project starts. Starting a second while the first is
running fails:

```text
ddev-router already running, pushing new config...
Failed to start kiritest-01UrTUMv: failed to update router network aliases: failed to disconnect
container 340d2de2… from network ddev_default: Error response from daemon: Kiri cannot disconnect a
running container from its first network (ddev_default); stop the container first
```

**Why.** When a project adds hostnames, DDEV updates the running router's
network aliases in place, by disconnecting it from `ddev_default` and
connecting it again with the new aliases
(`pkg/ddevapp/router.go`, `dockerutil.UpdateContainerNetworkAliases`). Docker
allows this on a running container. Kiri refuses it on purpose
(`crates/kiri/src/daemon/engine.rs`, `disconnect`): a container's first
network holds its default route, its main address (which published ports go
to) and its resolver, and moving those while it runs "needs the guest to do
more than unplug it".

**Options.**
- In Kiri: allow disconnect and reconnect of a running container's first
  network, at least when the same container is reconnected to the same network
  straight away (the alias-update pattern), or support changing aliases
  without a disconnect. That is a bigger change than #595, so an issue first.
- In DDEV (done on the branch above, and tested): if the in-place update
  fails, recreate the router as DDEV did before the in-place update existed.

## 6. A name on two networks resolves on the wrong one: projects see each other's services

- Upstream: [libracoder/kiri#294](https://github.com/libracoder/kiri/issues/294)
  (reported 2026-11-15, with DDEV as the example), **fixed on Kiri main by
  #581** on 2026-11-19, after 0.2.2. The draft in
  [issues/03-dns-network-order.md](../issues/03-dns-network-order.md) wasn't
  posted.
  Found on macOS 2026-11-22, Kiri 0.2.2
  ([results](../results/macos-20261122-arm64-brew.md#step-3-two-projects-share-db-problem-6)).
- Confirmed against Docker on 2026-11-23 (OrbStack 29.8.2 and Colima 29.5.2):
  a serious Kiri bug.
- DDEV workaround: none. **Run one project at a time on Kiri.**

**Symptom.** With two DDEV projects running, `db` in one project's web
container resolves to both projects' database containers, and
`mysql -h db` from the second project reached the first project's database
(`select @@hostname` → `kdns1-db` from `kdns2`). DDEV's
`TestNetworkAmbiguity` fails (`should have 1 item(s), but has 2`).

**Why.** Every DDEV service is on its project network and on the shared
`ddev_default`, and Compose gives each service its name as an alias on both,
so `db` is ambiguous on `ddev_default`.

Docker doesn't isolate names by network either. Tested with plain `docker`
on OrbStack and Colima: it answers from the container's networks **in
network-name order**, returning every match on the first network that has the
name, whatever order the networks were created or listed in. Rename the
networks so the shared one sorts first (`a-shared`, `z-p1net`) and Docker
returns both projects' `db` too. DDEV is safe on Docker only because
`ddev-<project>_default` sorts before `ddev_default` (`-` is 0x2d, `_` is
0x5f).

Kiri answers from the network **listed first in the create request**
(`--network aa --network zz` answers from `aa`, the reverse from `zz`, where
Docker answers from `aa` both times). For Compose-created DDEV containers that
is `ddev_default`, which holds every project's `db`. The full comparison
table is in the issue draft.

On OrbStack, two DDEV projects running at once each reach only their own
`db` (`mysql -h db` → `odns1-db` and `odns2-db`); on Kiri the second reached
the first's.

**Fix (in Kiri).** Resolve in Docker's order (by network name).

**Fix (in DDEV), which makes Kiri's order harmless:**
[ddev/ddev#9172](https://github.com/ddev/ddev/issues/9172) (history and
findings) asks for ddev/ddev#8995: `use_service_name_alias: false` on
`ddev_default`, so `db` doesn't exist there. Compose v5.8.0, which DDEV
vendors, supports it. Tried on 2026-11-23 in a scratch build (#9167 plus
#8995's change): on Kiri each of two projects reaches its own `db`, and with
one project's db stopped `db` doesn't resolve (on OrbStack too, which also
fixes ddev/ddev#8390). Implemented in draft PR
[ddev/ddev#9173](https://github.com/ddev/ddev/pull/9173); its
`TestNetworkAmbiguity` addition fails without the change on OrbStack.

## 7. `volume rm --force` removes a volume that a container uses

- Upstream: [libracoder/kiri#773](https://github.com/libracoder/kiri/issues/773)
  (filed 2026-11-23); still on main 099f22c (`engine.rs`, `volume_remove`:
  the in-use check is skipped when `force` is set).
- Fix: draft PR [libracoder/kiri#781](https://github.com/libracoder/kiri/pull/781)
  (`rfay:20261123_volume_rm_force_in_use`, one commit, signed by Randy). The
  in-use refusal no longer depends on `force`; `force` still overrides the
  damaged-list refusal. Its unit test fails without the change. The full
  `cargo test --workspace --exclude kiri-init` passes, and clippy and fmt
  report the same as main (in a `rust:1` container). Not yet run as a built
  engine against the #773 repro. Draft in
  [issues/02-volume-rm-force.md](../issues/02-volume-rm-force.md), with
  Docker's output from OrbStack (refused both times). Found on macOS
  2026-11-22, Kiri 0.2.2.

`docker volume rm kv` with a (stopped) container using `kv` is refused, as in
Docker. `docker volume rm -f kv` removes it, and the data is gone. Docker
refuses this even with force (checked on OrbStack). DDEV's `dockerutil.RemoveVolume()` always passes `Force: true` and
relies on the refusal to tell the user which containers hold the volume
(`TestRemoveVolumeInUseNamesContainer`). Data-loss risk, so worth filing.

## 8. Small differences (cosmetic for DDEV)

- A missing command: `docker run busybox nocommandbythatname` starts the
  container, which exits 127 with `kiri: cannot start container: … executable
  file not found in $PATH`. Docker fails the start request itself (and
  DDEV's `TestRunSimpleContainer` checks for `failed to start container`).
- `docker run --entrypoint '' IMAGE sh -c …` fails with
  `exec: "/usr/local/sbin/": is a directory: permission denied`. Docker treats
  an empty entrypoint as "none" and runs the command. DDEV doesn't do this
  itself, as far as seen.
- `exec` as a user that doesn't exist: Kiri writes
  `kiri: cannot start container: user: unknown user nosuchuser` to the exec's
  output and exits non-zero; Docker returns an API error and no output
  (`TestCmdExecTerminalChild/daemon_error`).

## 10. Image labels missing (0.2.2 only; fixed on Kiri main)

`docker image inspect` of an image DDEV built shows `Config.Labels=null`, and
`docker images --filter label=com.ddev.site-name` finds nothing. DDEV finds a
project's images by label, so on 0.2.2:

- `ddev delete` leaves the project's `*-built` images behind (disk use grows);
  `TestDeleteCmd` fails.
- `ddev utility check-custom-config` can't see which DDEV version a custom image
  was built for (`com.ddev.image-tag`); `TestUtilityCheckCustomConfigCmd` fails.

Kiri main has the fix: d80976c "Engine: expose image Config.Labels and inherit
image labels on container create" (libracoder/kiri#393). Needs a release.

## 11. `--volumes-from` mounts nothing (0.2.2 only; fixed on Kiri main)

`docker run --volumes-from ddev-ssh-agent busybox ls /tmp/.ssh-agent` →
`No such file or directory`, though `ddev-ssh-agent` has named volumes on
`/tmp/.ssh` and `/tmp/.ssh-agent`. So the default **`ddev auth ssh`** (which
adds keys through a helper container with `--volumes-from ddev-ssh-agent`)
fails on 0.2.2:

```text
Adding key id_rsa
Error connecting to agent: No such file or directory
Failed to execute command `ddev auth ssh`: container run failed with exit code 2
```

`ddev auth ssh -f <keyfile>` works, because it pipes the key into
`ssh-add -` through `exec` (that's how the 2026-11-20 run succeeded). Kiri
main has the fix: 46b32cd "eight Docker behaviour differences fixed
(--volumes-from, --pid, docker top, exposed ports, connection close)" (#588).

## 12. Images with more than 58 layers can't run: MySQL 8.4 and 9.7 are unusable

- Upstream: **fixed on Kiri main** by a3b8ff0 "Guest: images of 60 or more
  layers start" (libracoder/kiri#682, 2026-11-21, after 0.2.2): when the
  options don't fit in a page, the lower layers are named by short links. The
  `rfay/kiri` checkout used here (d80976c) was older. The draft in
  [issues/01-layer-limit.md](../issues/01-layer-limit.md) wasn't posted.
- DDEV workaround: none, other than another database type. `mysql:8.0` (37
  layers) and MariaDB (33–37) work. **DDEV's `mysql:8.4` and `mysql:9.7` images
  have 75 layers.**

**Symptom.** Any container from such an image fails to start:

```text
$ docker run --rm --entrypoint true ddev/ddev-dbserver-mysql-8.4:v1.25.6
docker: Error response from daemon: run 3efe58fd…: mount /var/lib/kiri/containers/3efe58fd…/rootfs:
No such file or directory (os error 2)
```

(`Invalid argument (os error 22)` for some layer counts.) In DDEV, a project
with `database: mysql:8.4` won't start, and
`ddev utility migrate-database mysql:8.4` leaves the project broken. Synthetic
images built `FROM busybox` with one `RUN` per layer: 40–58 layers run, 59, 60,
61 and 70 fail.

**Why.** `crates/kiri-init/src/linux/container.rs`, `mount_rootfs`, builds one
overlayfs mount whose `lowerdir=` lists every layer by its 64-character hex
name (relative to the layer store, about 65 bytes a layer), followed by the
absolute `upperdir` and `workdir`. The kernel takes mount options in one page
(4096 bytes): 58 × 65 = 3770 plus the two paths fits, 59 × 65 = 3835 plus
them doesn't.

**Fix (in Kiri).** As Docker's overlay2 does: short link names for the lower
directories (Docker uses 26-character ids under `l/`), or the
`lowerdir+=` option one layer at a time through `fsconfig()` (Linux 6.8+),
or flattening/merging layers above a threshold. File with the synthetic
repro: it needs nothing but busybox.

This was first seen as an apparent race (`TestDebugMigrateDatabase`, the db
container failing right after a build); it's this limit, reproducible every
time.

## 9. macOS: no ports below 1024 on 127.0.0.1

- Not a Kiri bug as such; macOS lets an unprivileged process bind ports below
  1024 only on the wildcard address, and Kiri's engine runs as the user.
- DDEV: use router ports 8080/8443 (as DDEV's CI does for rootless Podman and
  socktainer). The PR branch now says so when the router fails this way.

`docker run -p 127.0.0.1:80:80` fails on Kiri (`ports not published; container
stopped … Permission denied (os error 13)`, the container `Exited (137)`),
while `-p 80:80` and `-p 127.0.0.1:1080:80` work. Docker Desktop gets around
it with a helper that runs as root. Possible Kiri fix: a privileged helper
for low ports, or bind the wildcard address and accept only loopback
connections when a loopback address was asked for. Low priority; worth a
mention in Kiri's docs ("DDEV and other tools that publish 127.0.0.1:80 need
other ports").

## Upstream etiquette (from Kiri's CONTRIBUTING.md and PR template)

- Issue first, and agreement, for anything bigger than a small fix; at most 3 open PRs.
- Before/after output from a real machine; the issue form asks for the version, the commands, the output and what Docker does.
- Signed commits and a CLA (CLA Assistant asks on the first PR).
- The PR template asks whether AI tools were used and for which parts.
- Every feature should work on macOS, Windows and Linux in one PR. There's also a speed check (`scripts/perf.py`).
- The repo has no rustfmt or clippy config. `cargo fmt --check` and `cargo clippy -D warnings`
  already report findings on main with a current toolchain, so compare your
  branch against main rather than expecting a clean run.
