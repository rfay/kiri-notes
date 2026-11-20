# macOS testing plan (for a macOS agent)

**Status: projected, not yet run.** Nothing here has been tried on a Mac. It's
the plan for an agent on a Mac to repeat the Linux evaluation and report back.
Adjust it where reality differs, and record every difference.

## Goal

Find out whether DDEV works with Kiri as its Docker provider on macOS, and
provide the macOS evidence for [libracoder/kiri#595](https://github.com/libracoder/kiri/pull/595):

1. **Baseline:** released Kiri with released DDEV. Expected to fail at
   `ddev start` because of [libracoder/kiri#594](https://github.com/libracoder/kiri/issues/594),
   unless a Kiri release includes #595.
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
brew install ddev/ddev/ddev mkcert go jq
mkcert -install                       # once, if DDEV hasn't already done it
git clone https://github.com/rfay/kiri-notes ~/kiri-test/kiri-notes
mkdir -p ~/kiri-test/proj ~/kiri-test/ddev-config/ddev
```

The smoke test needs `jq`, `curl` and `python3` (Xcode Command Line Tools). Go is for building DDEV in step 4; Rust (`rustup`) is for building Kiri in step 5.

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

- `0 0 600` and `Permission denied`: bug #594 is present, so expect `ddev start` to fail.
- `1234 1235 600` and `key`: a release has the fix. Note it, skip the Kiri
  build in step 5, and use `kiri` wherever this plan says `kiri-ddev`.

```bash
scripts/ddev-smoke-test.sh ~/kiri-test/proj/baseline kiribase
```

With #594 present, expect `FAIL ddev start`, with the web container exiting on
`failed to read the CA key … permission denied`. Record that output and
`ddev logs -s web | tail -30`, then `ddev delete -Oy kiribase`.

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
cargo xtask kernel        # guest/out/Image
cargo xtask disk          # guest/out/data.img
cargo xtask guest         # guest/out/initramfs.cpio; this is where the fix lives (kiri-init)
cargo xtask app-dev ddev  # target/dev/Kiri Ddev.app: a second Kiri with its own engine
open "target/dev/Kiri Ddev.app"
docker context ls         # find the new Kiri's context; e2e.sh's naming suggests kiri-ddev
```

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

Expected:
- `cp-in-keeps-owner` passes on `kiri-ddev` and fails on the released `kiri`.
- No other check fails on `kiri-ddev` that also passes on the released Kiri.
  Some checks may fail on both (environment, Finder, domains, Kubernetes …).
  List those, but they don't count against the PR.

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
`failed to update router network aliases … Kiri cannot disconnect a running
container from its first network`. Record it. Then:

```bash
ddev stop kirinone
PERFORMANCE_MODE=mutagen scripts/ddev-smoke-test.sh ~/kiri-test/proj/mutagen kirimutagen
ddev stop kirimutagen && ddev start kirinone
```

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
   9003 on the Mac (`nc -l 9003`) and run `ddev exec 'XDEBUG_SESSION=1 php -r "echo 1;"'`.
   A connection should arrive.
2. **File speed**, compared with the normal provider if possible:
   `time ddev composer create-project drupal/recommended-project:^11 --no-interaction`
   in a fresh `drupal11` project, with `none` and with `mutagen`.
3. **A real CMS:** that Drupal project, then
   `ddev drush si -y --account-pass=admin` and `curl` its front page through the
   router (expect `200`). Optionally a WordPress quickstart too.
4. **amd64 image through Rosetta:** a project with `ddev config --database=mysql:5.7`
   (no arm64 image). On Apple silicon it should start, slowly. Record the time.
5. **Idle VM sleep:** Kiri's VM sleeps after 60 s idle. With a project running,
   wait 3 minutes, then `curl` the site and `ddev exec true`. Does the project still
   answer, and how long does the first request take?
6. **SSH agent:** `ddev auth ssh`, then `ddev exec ssh-add -l` lists your keys.
   Kiri forwards the agent at `/run/host-services/ssh-auth.sock`.
7. **Restart of Kiri itself:** quit and reopen Kiri, then `ddev start` the
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
