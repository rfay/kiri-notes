# macOS testing plan (for a macOS agent)

**Status: run once,** on an M1 Mac with macOS 27.2.1 on 2026-11-20
([results/macos-20261120-arm64.md](../results/macos-20261120-arm64.md)). The
steps below include the corrections from that run. Adjust it where reality
differs again, and record every difference.

## Goal

Find out whether DDEV works with Kiri as its Docker provider on macOS, and
provide the macOS evidence for [libracoder/kiri#595](https://github.com/libracoder/kiri/pull/595):

1. **Baseline:** released Kiri with released DDEV. DDEV v1.25.5 passes, because
   it doesn't copy the mkcert CA into the container. DDEV main after v1.25.5
   does, and fails at `ddev start` because of
   [libracoder/kiri#594](https://github.com/libracoder/kiri/issues/594),
   unless a Kiri release includes #595. Note which DDEV you're testing.
2. **DDEV workaround:** released Kiri with DDEV built from
   [`rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`](https://github.com/rfay/ddev/compare/main...rfay:ddev:20261120_rfay_kiri_ca_copyuidgid).
   Expected to work, including two projects at once.
3. **Kiri fix:** Kiri built from #595's branch. Verify the fix and run Kiri's
   own e2e suite, so #595's "works on macOS" checkbox can be ticked.
4. **Two projects at once** with released DDEV. Expected to fail on the router
   network disconnect (problem 5 in [kiri-fixes.md](kiri-fixes.md)) whatever the Kiri build.
5. **macOS-specific points:** Xdebug via `host.docker.internal`, bind-mount
   ownership and speed on virtiofs, Mutagen, router ports, the VM sleeping when
   idle, amd64 images, and a real CMS.

## Ground rules for the agent

- Don't disturb the Mac's existing Docker provider (Docker Desktop, OrbStack,
  Colima …) or its DDEV projects. Never change the default docker context.
  Pass `DOCKER_CONTEXT=kiri` (or the dev Kiri's context) to every command instead.
- Give DDEV its own global config for every command run against Kiri:
  `export DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config`. DDEV's project list and
  router are then separate from the normal ones.
- Don't run `ddev poweroff`, `docker system prune` or anything else global against the normal provider.
- Record versions: `sw_vers`, `uname -m`, `ddev version`, `kiri version` (or
  Kiri's About window), and `docker --context kiri version`.
- Write results to `results/macos-<YYYYMMDD>-<arch>.md` in this repository:
  versions, the full smoke-test output for each run, and for each failure the
  command, the output, and the relevant logs (`ddev logs -s web`, Kiri's log).
  Don't open upstream issues; a person reviews the results first.

## 0. Prerequisites

```bash
brew install mkcert go jq
mkcert -install                       # once, if DDEV hasn't already done it
git clone https://github.com/rfay/kiri-notes ~/kiri-test/kiri-notes
mkdir -p ~/kiri-test/proj ~/kiri-test/ddev-config/ddev ~/kiri-test/bin
```

Released DDEV: if the Mac already has `ddev`, don't upgrade or replace it,
since its owner uses it. Put the release you're testing in `~/kiri-test/bin`
from the `macos-arm64` tarball on the DDEV releases page, and call it by its
full path or with `PATH=~/kiri-test/bin:$PATH`. Run `ddev --version` before
each test.

The smoke test needs `jq`, `curl` and `python3` (Xcode Command Line Tools). Go is for building DDEV in step 4; Rust (`rustup`) is for building Kiri in step 5.
If `rustup` and `cargo` shouldn't touch the Mac's own `~/.cargo`, set
`CARGO_HOME` and `RUSTUP_HOME` to folders under `~/kiri-test`.

On a shared or agent-run Mac, a scratch folder other than `~/kiri-test` is
fine (the 2026-11-20 run used `~/tmp/<session>/kiri-test`). It must be under
the home directory.

Use paths under the home directory. Kiri shares Mac paths into its VM over
virtiofs, so check where the default shares are before using another location.

## 1. Install the released Kiri

```bash
brew install --cask libracoder/kiri/kiri
open -a Kiri
```

Opening it the first time runs `kiri setup`, which creates the `kiri` docker
context. The app may ask about `*.kiri.local` domains: **decline**, or turn
them off later in Settings → Domains. With domains on, Kiri holds host ports
80 and 443, which DDEV's router also wants.

**Without the app (agent, or no one at the desktop):** opening the app shows
dialogs and can ask for an administrator password. Run the engine directly
instead, with Kiri's own routers moved off 80/443, and create the context
yourself:

```bash
(KIRI_HTTP_PORT=38080 KIRI_HTTPS_PORT=38443 nohup /Applications/Kiri.app/Contents/MacOS/kiri daemon \
  >> ~/kiri-test/kiri-daemon.log 2>&1 &)
docker context create kiri --docker host=unix://$HOME/.kiri/run/docker.sock
```

Kiri's routers listen on all addresses at 80/443 by default, even next to
another provider (OrbStack) that already holds those ports. `KIRI_HTTP_PORT`
and `KIRI_HTTPS_PORT` move them. Kiri's own logs are in `~/.kiri/logs/`
(`daemon.log`, `guest-console.log`, `cli.log`).

```bash
docker context ls
docker --context kiri run --rm alpine echo hello
```

## 2. DDEV global config for Kiri

Seed it from the normal one, then move every port so it can't collide with the
normal provider's DDEV router or with Kiri's own 80/443:

```bash
export DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config DOCKER_CONTEXT=kiri
cp ~/.ddev/global_config.yaml $DDEV_XDG_CONFIG_HOME/ddev/ 2>/dev/null || true
ddev config global --router-http-port=28080 --router-https-port=28443 \
  --mailpit-http-port=28025 --mailpit-https-port=28026 --traefik-monitor-port=20999 \
  --instrumentation-opt-in=false
```

If the normal provider's DDEV router isn't running and Kiri's domains are off,
also do one run with the default ports (80/443) to check plain `https://<name>.ddev.site`.

## 3. Baseline: released Kiri, released DDEV

```bash
cd ~/kiri-test/kiri-notes
export DOCKER_CONTEXT=kiri DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
scripts/repro-archive-owners.sh kiri
```

- `0 0 600` and `Permission denied`: bug #594 is present, so expect `ddev start`
  to fail with DDEV main after v1.25.5. v1.25.5 itself passes (see the Goal).
- `1234 1235 600` and `key`: a release has the fix. Note it, skip the Kiri
  build in step 5, and use `kiri` wherever this plan says `kiri-ddev`.

```bash
scripts/ddev-smoke-test.sh ~/kiri-test/proj/baseline kiribase
```

With #594 present and a DDEV that copies the CA (main after v1.25.5), expect
`FAIL ddev start`, with the web container exiting on
`failed to read the CA key … permission denied`. Record that output and
`ddev logs -s web | tail -30`, then `ddev delete -Oy kiribase`. With v1.25.5,
expect every check to pass.

Also start a second project with released DDEV while `kiribase` runs, to
record problem 5 on the released Kiri (`FAIL ddev start`, `Kiri cannot
disconnect a container from its first network (ddev_default)`).

Between steps, free the alternate ports by stopping Kiri's DDEV router, scoped
to Kiri: `DOCKER_CONTEXT=kiri DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config ddev poweroff`.
Never run it without both variables.

## 4. Released Kiri with the DDEV workaround branch

Build DDEV from the branch. Use it only through its full path or a `PATH`
prefix in this step; don't install it over the normal `ddev`.

```bash
git clone --branch 20261120_rfay_kiri_ca_copyuidgid https://github.com/rfay/ddev ~/kiri-test/ddev
cd ~/kiri-test/ddev && make
DDEVWA=~/kiri-test/ddev/.gotmp/bin/$(go env GOOS)_$(go env GOARCH)
$DDEVWA/ddev --version
```

Then two projects, the second started while the first runs:

```bash
cd ~/kiri-test/kiri-notes
export DOCKER_CONTEXT=kiri DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
PATH=$DDEVWA:$PATH scripts/ddev-smoke-test.sh ~/kiri-test/proj/wa1 kiriwa1
PATH=$DDEVWA:$PATH scripts/ddev-smoke-test.sh ~/kiri-test/proj/wa2 kiriwa2
curl -s --resolve kiriwa1.ddev.site:28080:127.0.0.1 http://kiriwa1.ddev.site:28080/   # first project still answers
PATH=$DDEVWA:$PATH ddev delete -Oy kiriwa1; PATH=$DDEVWA:$PATH ddev delete -Oy kiriwa2
```

Expected: every check passes in both, and the second start prints
`Starting ddev-router` (the router is recreated) rather than an error.

## 5. Build Kiri with the fix (#595)

From [docs/development.md](https://github.com/libracoder/kiri/blob/main/docs/development.md).
It needs Rust (`rustup`), the Xcode Command Line Tools, and a Docker engine
for the kernel, disk and guest builds; the installed Kiri can be that engine.

```bash
git clone https://github.com/rfay/kiri ~/kiri-test/kiri
cd ~/kiri-test/kiri && git checkout 20261119_rfay_archive_keep_owners && git log -1 --oneline   # 251697c
export DOCKER_CONTEXT=kiri
rustup target add aarch64-unknown-linux-musl
# The fix is only in the initramfs (kiri-init). The released kernel and disk
# are the same, and building them takes a long time, so reuse the app's:
mkdir -p guest/out
cp /Applications/Kiri.app/Contents/Resources/guest/Image guest/out/
tar -xzf /Applications/Kiri.app/Contents/Resources/guest/data.img.tgz -C guest/out   # data.img, sparse
# (or build them: cargo xtask kernel; cargo xtask disk)
cargo xtask guest         # guest/out/initramfs.cpio; this is where the fix lives (kiri-init)
cargo xtask app-dev ddev  # target/dev/Kiri Ddev.app: a second Kiri with its own engine
open "target/dev/Kiri Ddev.app"
docker context ls         # find the new Kiri's context; e2e.sh's naming suggests kiri-ddev
```

Without the app, as in step 1:

```bash
nohup "target/dev/Kiri Ddev.app/Contents/MacOS/kiri" daemon > ~/kiri-test/kiri-ddev-daemon.log 2>&1 &
docker context create kiri-ddev --docker host=unix://$HOME/.kiri-ddev/run/docker.sock
```

The dev flavor keeps its state in `~/.kiri-ddev` and starts no
`*.kiri.localhost` routers, so it doesn't need the port variables. On an M1
with 8 GiB, `cargo xtask guest` took 6 minutes and `app-dev` 7, from a clean
checkout. Both engines ran at the same time without trouble.

On an Intel Mac, add `--arch x86_64` to `kernel`, `guest` and `app-dev`.
`app-dev` builds with the fast profile, so it's a little slower than a release
build. That's fine for correctness, but say so next to any timings.

If `app-dev` doesn't work out, `cargo xtask host` and
`./target/release/kiri daemon &` with `KIRI_DATA_DIR` set to a new directory
is the other documented way. Then create a context for its socket by hand
(`docker context create kiri-ddev --docker host=unix://…`, using the socket
path it prints).

Keep the released Kiri installed: step 6 compares the two. Record whether
both engines ran at the same time or one was quit while the other ran.

## 6. Verify #595 on macOS (for the PR's checkbox)

The PR is tested on Linux only. Its "works on macOS, Windows and Linux"
checkbox needs macOS evidence; Windows stays untested.

```bash
cd ~/kiri-test/kiri-notes
scripts/repro-archive-owners.sh kiri-ddev    # expect: 1234 1235 600 / key
scripts/repro-archive-owners.sh kiri         # released, expect: 0 0 600 / Permission denied
```

Then Kiri's own e2e suite, from the PR branch, against both engines. It has no
way to run one section, so run all of it and keep each log:

```bash
cd ~/kiri-test/kiri
DOCKER_CONTEXT=kiri-ddev tests/e2e.sh 2>&1 | tee ~/kiri-test/e2e-fixed.log
DOCKER_CONTEXT=kiri      tests/e2e.sh 2>&1 | tee ~/kiri-test/e2e-released.log
grep -E 'FAIL|cp-in-|^== docker cp|passed|failed' ~/kiri-test/e2e-fixed.log | tail -30
```

On the 2026-11-20 run, the Finder mounts (`~/Kiri`, `~/Kiri Ddev`) were
mounted but every access hung, with engines started by hand as above. The
suite then stalled in its Finder section for more than 20 minutes and never
finished. If `perl -e 'alarm 10; exec @ARGV' ls ~/"Kiri Ddev"` times out,
record it and run a copy of the suite with that section disabled:

```bash
s=$(grep -n '^section "container files in Finder' tests/e2e.sh | cut -d: -f1)
e=$(grep -n '^section "volumes and bind mounts"' tests/e2e.sh | cut -d: -f1)
awk -v s=$s -v e=$((e-1)) 'NR==s{print "if false; then"} {print} NR==e{print "fi"}' tests/e2e.sh > tests/e2e-nofinder.sh
chmod +x tests/e2e-nofinder.sh
```

An interrupted run leaves its containers behind (the cleanup trap doesn't
run). On a dev engine that only the suite uses, remove them before the rerun:
its container names would collide.

Expected:
- `cp-in-keeps-owner` passes on `kiri-ddev` and fails on the released `kiri`.
- No other check fails on `kiri-ddev` that also passes on the released Kiri.
  Some checks may fail on both (environment, Finder, domains, Kubernetes …).
  List those, but they don't count against the PR.
- The released Kiri fails many more checks than the fixed one (68 against 1
  on 2026-11-20). The suite comes from the PR branch, which is based on a main
  newer than the release, so it tests features 0.2.2 doesn't have. Compare
  `cp-in-keeps-owner` and look for checks that fail only on the fixed build;
  don't read the released total as a regression list.
- `host-net` expects the VM's address to start with `192.168.64.`. On a Mac
  where other Virtualization.framework VMs (OrbStack, Lima, Apple's container)
  already use that subnet, Kiri gets `192.168.65.x`, and the check fails on
  both engines. That's environmental.

Put a short summary in the results file under **"For libracoder/kiri#595"**,
written so it can be pasted as a PR comment: macOS version, chip, the PR
commit, the two repro outputs, the e2e totals for both engines, and the
`docker cp` section lines. Don't post it; a person does.

## 7. Smoke test with the fixed Kiri and released DDEV

One project at a time, since released DDEV can't start a second project while
the router runs on Kiri (problem 5):

```bash
cd ~/kiri-test/kiri-notes
export DOCKER_CONTEXT=kiri-ddev DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
PERFORMANCE_MODE=none    scripts/ddev-smoke-test.sh ~/kiri-test/proj/none    kirinone
PERFORMANCE_MODE=mutagen scripts/ddev-smoke-test.sh ~/kiri-test/proj/mutagen kirimutagen   # while kirinone runs
```

Expected: `kirinone` passes everything. `kirimutagen`, started while
`kirinone` is running, is expected to `FAIL ddev start` with
`failed to update router network aliases … Kiri cannot disconnect a container
from its first network (ddev_default)` (the macOS wording on Kiri 0.2.2). Record it. Then:

```bash
ddev stop kirinone kirimutagen
ddev poweroff      # with DOCKER_CONTEXT=kiri-ddev and DDEV_XDG_CONFIG_HOME set: removes Kiri's router
PERFORMANCE_MODE=mutagen scripts/ddev-smoke-test.sh ~/kiri-test/proj/mutagen kirimutagen
ddev stop kirimutagen && ddev poweroff && ddev start kirinone
```

`ddev stop kirinone` alone isn't enough (2026-11-20): the failed `kirimutagen`
start leaves that project's containers running, and the router outlives
stopped projects. Any start that adds hostnames to a running router then hits
problem 5 again, even with no other project running. Only removing the router
(a scoped `ddev poweroff`) clears it. Released DDEV's `ddev restart` of the
same project is fine, since its hostnames don't change.

`ROUTER_IP` defaults to `127.0.0.1`, which is right on a Mac if Kiri forwards
published ports to localhost.

Pay particular attention to:

- **`web container reaches host via host.docker.internal`**: the real Xdebug path.
  DDEV adds no `extra_hosts` on macOS for a generic provider, so this relies on
  Kiri's built-in `host.docker.internal`. If it fails, record what
  `ddev exec getent hosts host.docker.internal` returns and whether
  `198.19.248.254` (Kiri's documented Mac gateway) works.
- **The bind-mount ownership checks** with `none`: virtiofs and the Mac uid (501).
- **Mutagen:** `ddev mutagen st` is healthy and a host edit shows up in the container.

## 8. macOS-specific checks

Run these on `kiri-ddev` against the `kirinone` project unless noted, one
project running at a time, and record the output of each:

1. **Xdebug end to end:** `ddev xdebug on`, then
   `ddev exec 'php -r "var_dump(ini_get(\"xdebug.client_host\"));"'`. Listen on
   9003 on the Mac on 0.0.0.0 (a small Python `socket` listener worked;
   `nc -l 9003` received nothing on 2026-11-20) and run `ddev exec 'XDEBUG_SESSION=1 php -r "echo 1;"'`.
   A connection should arrive.
2. **File speed**, compared with the normal provider if possible:
   `time ddev composer create-project drupal/recommended-project:^11 --no-interaction`
   in a fresh `drupal11` project, with `none` and with `mutagen`.
3. **A real CMS:** that Drupal project, then
   `ddev drush si -y --account-pass=admin` and `curl` its front page through the
   router (expect `200`). Optionally a WordPress quickstart too.
4. **amd64 image through Rosetta:** DDEV's `mysql:5.7` image has an arm64
   build now (2026-11-20: `@@version_compile_machine` was `aarch64`), so a
   `--database=mysql:5.7` project is worth timing but doesn't exercise Rosetta.
   For Rosetta, run `docker run --rm --platform linux/amd64 alpine uname -m`
   (expect `x86_64`), and check the `rosetta-*` lines of the e2e run.
5. **Idle VM sleep:** Kiri's VM sleeps after 60 s idle. With a project running,
   wait 3 minutes, then `curl` the site and `ddev exec true`. Does the project still
   answer, and how long does the first request take?
6. **SSH agent:** `ddev auth ssh`, then `ddev exec ssh-add -l` lists your keys.
   Kiri forwards the agent at `/run/host-services/ssh-auth.sock`.
7. **Restart of Kiri itself:** quit and reopen Kiri (or, with an engine
   started by hand, `kill` it and start it again: if it logs
   `engine shutting down` but keeps running, look for a process stuck on the
   Finder mount, since shutdown waits on `umount -f`), then `ddev start` the
   project again. Record whether the project comes back and how long Kiri
   takes to answer `docker ps` after reopening.
8. **Optional, DDEV's own tests:** in a `ddev/ddev` checkout,
   `DOCKER_CONTEXT=kiri-ddev make testpkg TESTARGS="-run TestDdevStart"`. These
   tests run `ddev poweroff` and use the global config, so run them only with
   `DOCKER_CONTEXT` and `DDEV_XDG_CONFIG_HOME` pointing at Kiri, never at the normal provider.

## 9. Cleanup

```bash
export DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
for p in kirinone kirimutagen drupal11; do DOCKER_CONTEXT=kiri-ddev ddev delete -Oy $p; done
for p in kiribase kiriwa1 kiriwa2; do DOCKER_CONTEXT=kiri ddev delete -Oy $p; done
```

Some of these may already be gone. Quit `Kiri Ddev.app`. Leave the released
Kiri installed unless asked to remove it (`brew uninstall --cask kiri`; its
data is in `~/Library/Application Support/Kiri`). `~/kiri-test` can stay
until the results are reviewed.

## What to report

In `results/macos-<YYYYMMDD>-<arch>.md`, committed and pushed to this repository:

- versions (macOS, chip, DDEV released and branch build, Kiri released and the built commit, other provider present);
- step 3 (baseline) and step 4 (DDEV workaround, two projects);
- **"For libracoder/kiri#595"** (step 6), ready to paste as a PR comment;
- step 7's smoke results, including the expected second-project failure;
- each check in step 8: pass or fail, timings, and logs for failures;
- anything in this plan that was wrong or needed changing, with the change made.
