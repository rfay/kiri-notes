# What has to be fixed in Kiri for DDEV

Code references are to `libracoder/kiri` main at `d80976c` (Kiri 0.2.2 plus a few commits).

## 1. Copy-in drops the archive's owners: breaks DDEV everywhere

- Upstream: issue [libracoder/kiri#594](https://github.com/libracoder/kiri/issues/594), PR [libracoder/kiri#595](https://github.com/libracoder/kiri/pull/595)
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

## 4. Engine container restart (not reported)

In the nested setup, `docker stop` and then `docker start` of the engine
container makes every `docker run` fail with `VM did not boot: File exists (os error 17)`
(engine log: `ERROR VM did not boot error=File exists (os error 17)`).
Removing and recreating the container (keeping the same data volumes) works.
It's probably about the agent's cgroup or lock state under `--cgroupns private`,
but it hasn't been investigated. `scripts/run-kiri-engine.sh` always creates a
fresh container to avoid it.

## Upstream etiquette (from Kiri's CONTRIBUTING.md and PR template)

- Issue first, and agreement, for anything bigger than a small fix; at most 3 open PRs.
- Before/after output from a real machine; the issue form asks for the version, the commands, the output and what Docker does.
- Signed commits and a CLA (CLA Assistant asks on the first PR).
- The PR template asks whether AI tools were used and for which parts.
- Every feature should work on macOS, Windows and Linux in one PR. There's also a speed check (`scripts/perf.py`).
- The repo has no rustfmt or clippy config. `cargo fmt --check` and `cargo clippy -D warnings`
  already report findings on main with a current toolchain, so compare your
  branch against main rather than expecting a clean run.
