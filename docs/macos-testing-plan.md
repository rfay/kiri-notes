# macOS testing plan (for a macOS agent)

**Status: projected, not yet run.** Nothing here has been tried on a Mac. It's
the plan for an agent on a Mac to repeat the Linux evaluation and report back.
Adjust it where reality differs, and record every difference.

## Goal

Find out whether DDEV works with Kiri as its Docker provider on macOS:

1. with the **released** Kiri (expected to fail at `ddev start` because of
   [libracoder/kiri#594](https://github.com/libracoder/kiri/issues/594), unless a
   release includes [#595](https://github.com/libracoder/kiri/pull/595));
2. with Kiri **built from the fix branch**;
3. on the macOS-specific points: Xdebug via `host.docker.internal`, bind-mount
   ownership and speed on virtiofs, Mutagen, router ports, the VM sleeping
   when idle, amd64 images, and a real CMS.

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
brew install ddev/ddev/ddev mkcert
mkcert -install                       # once, if DDEV hasn't already done it
git clone https://github.com/rfay/kiri-notes ~/kiri-test/kiri-notes
mkdir -p ~/kiri-test/proj ~/kiri-test/ddev-config/ddev
```

The smoke test needs `python3` and `curl` (both come with macOS / Xcode Command Line Tools).

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

## 3. Baseline: released Kiri

```bash
cd ~/kiri-test/kiri-notes
scripts/repro-archive-owners.sh kiri
```

- `0 0 600` and `Permission denied` means bug #594 is still present: expect `ddev start` to fail.
- `1234 1235 600` and `key` means the fix has shipped: skip step 4 and use `kiri` as the context in step 5.

```bash
scripts/ddev-smoke-test.sh ~/kiri-test/proj/baseline kiribase
```

With #594 present, expect `FAIL ddev start` with the web container exiting on
`failed to read the CA key … permission denied`. Record that output and
`ddev logs -s web | tail -30`, then `ddev delete -Oy kiribase`.

## 4. Build Kiri with the fix

From [docs/development.md](https://github.com/libracoder/kiri/blob/main/docs/development.md).
It needs Rust (`rustup`), the Xcode Command Line Tools, and a Docker engine
for the kernel, disk and guest builds; the installed Kiri can be that engine.

```bash
git clone https://github.com/rfay/kiri ~/kiri-test/kiri
cd ~/kiri-test/kiri && git checkout 20261119_rfay_archive_keep_owners
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

Then quit the released Kiri (menu bar → Quit) so only one engine runs, unless
the two are clearly independent. Record which way you did it.

## 5. Smoke test with the fixed Kiri

```bash
cd ~/kiri-test/kiri-notes
export DOCKER_CONTEXT=kiri-ddev DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
scripts/repro-archive-owners.sh kiri-ddev            # expect 1234 1235 600 / key
PERFORMANCE_MODE=none    scripts/ddev-smoke-test.sh ~/kiri-test/proj/none    kirinone
PERFORMANCE_MODE=mutagen scripts/ddev-smoke-test.sh ~/kiri-test/proj/mutagen kirimutagen
```

`ROUTER_IP` defaults to `127.0.0.1`, which is right on a Mac if Kiri forwards
published ports to localhost.

Every check should pass. Pay particular attention to:

- **`web container reaches host via host.docker.internal`**: the real Xdebug path.
  DDEV adds no `extra_hosts` on macOS for a generic provider, so this relies on
  Kiri's built-in `host.docker.internal`. If it fails, record what
  `ddev exec getent hosts host.docker.internal` returns and whether
  `198.19.248.254` (Kiri's documented Mac gateway) works.
- **The bind-mount ownership checks** with `none`: virtiofs and the Mac uid (501).
- **Mutagen:** `ddev mutagen st` is healthy and a host edit shows up in the container.

## 6. macOS-specific checks

Run these against the `kirinone` project unless noted, and record the output of each:

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
   project again. In the nested Linux setup, restarting the engine container
   broke every `docker run` (`VM did not boot: File exists`), so record whether
   anything like that happens on the Mac.
8. **Optional, DDEV's own tests:** in a `ddev/ddev` checkout,
   `DOCKER_CONTEXT=kiri-ddev make testpkg TESTARGS="-run TestDdevStart"`. These
   tests run `ddev poweroff` and use the global config, so run them only with
   `DOCKER_CONTEXT` and `DDEV_XDG_CONFIG_HOME` pointing at Kiri, never at the normal provider.

## 7. Cleanup

```bash
export DDEV_XDG_CONFIG_HOME=~/kiri-test/ddev-config
for p in kiribase kirinone kirimutagen; do DOCKER_CONTEXT=kiri-ddev ddev delete -Oy $p; done
```

Quit `Kiri Ddev.app`. Leave the released Kiri installed unless asked to remove it
(`brew uninstall --cask kiri`; its data is in `~/Library/Application Support/Kiri`).

## What to report

In `results/macos-<YYYYMMDD>-<arch>.md`:

- versions (macOS, chip, DDEV, Kiri released and built commit, other provider present);
- the baseline result (step 3) and smoke results for `none` and `mutagen` (step 5);
- each check in step 6: pass or fail, timings, and logs for failures;
- anything in this plan that was wrong or needed changing, with the change made.
