# macOS results, 2026-11-22, arm64: Homebrew Kiri with DDEV PR #9167

Run by an agent on the shared Mac test machine, against Kiri 0.2.2 installed
with Homebrew and **opened as a normal app** (on 2026-11-20 the engines were
started by hand with `kiri daemon`). The question was whether
[ddev/ddev#9167](https://github.com/ddev/ddev/pull/9167) makes DDEV work on
released Kiri on a Mac, without the Kiri fix (libracoder/kiri#595).

## Summary

- **Yes, #9167 works on Homebrew Kiri 0.2.2**, once the router uses
  unprivileged ports. Two projects ran at once, 18/18 smoke checks each. The
  mkcert CA in the web container belongs to the Mac user (`505 20`), and the
  second start recreated the router instead of failing.
- **Control:** the PR's base (main 85dcf05) fails on the same Kiri with
  `ERROR: failed to read the CA key: open /usr/local/lib/ddev/mkcert/rootCA-key.pem: permission denied`
  (#594), as on Linux.
- **New: Kiri on macOS can't publish ports below 1024 on 127.0.0.1**, so DDEV's
  router can't use its defaults (80/443 on 127.0.0.1). It's a macOS rule, not a
  Kiri bug as such; see "Why 0.0.0.0:80 works and 127.0.0.1:80 doesn't".
  Fix: `ddev config global --router-http-port=8080 --router-https-port=8443`,
  as DDEV's CI already does for rootless Podman and Apple Container
  (socktainer).
- **New and serious: two running projects share service names.** With two
  projects running, `db` in one project's web container resolves to both
  projects' database containers, and `mysql -h db` from the second project
  connected to the **first** project's database. Docker answers from the
  project's own network. See problem 6. Until Kiri fixes this, run one project
  at a time on Kiri, whatever DDEV version.
- **New: `docker volume rm -f` removes a volume a stopped container uses**,
  and its data with it. Docker refuses even with force. Problem 7.
- **New: images with more than 58 layers can't start** on Kiri (any
  platform, Kiri main too). DDEV's `mysql:8.4` and `mysql:9.7` have 75, so
  those database types don't work at all. Problem 12.
- **DDEV's automated tests** (full `testpkg` and `testcmd`, about 680 passed):
  every failure is explained below. The Kiri causes are problems 5–12 (two of
  them already fixed on Kiri main); the rest are DDEV test issues or this
  machine. DDEV-side fixes were pushed to the PR branch (2f098e9, bbe3b7a,
  febdd83).

## Versions

| What | Version |
|---|---|
| Mac | Apple M1, arm64, macOS 27.2.1 (26B131) |
| Kiri | 0.2.2, Homebrew cask `libracoder/kiri/kiri`, app opened normally (LaunchAgent `dev.kiri.daemon`), context `kiri`; `/var/run/docker.sock` links to `~/.kiri/run/docker.sock` |
| Kiri settings | domains on, moved to 38080/38443 (`~/.kiri/domains.json`, from the earlier run) |
| DDEV | `rfay/ddev:20261120_rfay_kiri_ca_copyuidgid`: 1fb3805 (the PR as opened) for the smoke tests; 2f098e9 (+ Kiri detection) for the test suites; bbe3b7a and febdd83 (test fixes) for the reruns |
| DDEV control | ddev/ddev main 85dcf05 (the PR's base) |
| docker CLI | 29.10.0 |
| Go | 1.27.4 |

Every command ran with `DOCKER_CONTEXT=kiri` and
`DDEV_XDG_CONFIG_HOME=~/tmp/<session>/ddev-config`, whose global config sets
router ports 8080/8443.

## How to use Homebrew Kiri with DDEV on macOS

```bash
brew install --cask libracoder/kiri/kiri
open -a Kiri                      # creates the `kiri` docker context
docker context use kiri           # or: export DOCKER_CONTEXT=kiri
ddev config global --router-http-port=8080 --router-https-port=8443
```

Then use a DDEV build with #9167 (until it or libracoder/kiri#595 lands):

```bash
ddev utility download-ddev --pr 9167
export PATH="$HOME/tmp/ddev-download-ddev/pr-9167:$PATH"
ddev --version
```

Projects are at `https://<name>.ddev.site:8443`. Run **one project at a
time** (problem 6). Don't use `mysql:8.4` or `mysql:9.7` (problem 12). Add SSH
keys with `ddev auth ssh -f <keyfile>` (problem 11). Every project must use the unprivileged ports: a project
with `router_http_port: 80` in its own config, or one started earlier with the
old global ports, makes the router ask for 127.0.0.1:80 again (see below).

## Step 1: the router can't start with default ports

Someone had already started a Drupal project (`d11`) on Kiri with released
DDEV and the default `~/.ddev`. Its router was `Exited (137)`. Kiri's log:

```text
container create id=54a8bc253997 name=ddev-router image=ddev/ddev-traefik-router:v1.25.6
WARN  ports not published; container stopped id=54a8bc253997 error=Permission denied (os error 13)
WARN  request failed method=POST path=/containers/54a8…/start status=409
```

Plain docker on Kiri:

| `docker run -p …` | Result |
|---|---|
| `127.0.0.1:80:80` | fails, container `Exited (137)` |
| `80:80` (all interfaces) | runs, `0.0.0.0:80->80/tcp` |
| `127.0.0.1:1080:80` | runs |

### Why 0.0.0.0:80 works and 127.0.0.1:80 doesn't

Kiri's engine runs as the logged-in user, and it publishes a port by binding
it on the Mac itself. Since macOS 10.14 (Mojave), the kernel lets an
unprivileged process bind a port below 1024 **only on the wildcard address**
(`0.0.0.0` or `::`). Binding a specific address, including `127.0.0.1`, on such
a port still needs root. The same check without Kiri, as uid 505:

```text
0.0.0.0 :81 bind OK
127.0.0.1 :81 [Errno 13] Permission denied
:: :81 bind OK
```

(Python's `socket.bind()`.) DDEV's router publishes on `127.0.0.1` unless
`router_bind_all_interfaces: true`, so it hits the restricted case. Docker
Desktop avoids it with a helper that runs as root (`com.docker.vmnetd`,
installed when you give it your password). OrbStack also held
127.0.0.1:80/443 for DDEV on this Mac in the 2026-11-20 run; how it does that
wasn't checked. Kiri has no such helper for ports. It did ask for administrator
rights here (the `/var/run/docker.sock` link is owned by root), but not
for this. Kiri's own domains feature binds `*:80` and `*:443`, which is why it
works.

Ways around it, best first:

1. Unprivileged router ports (`ddev config global --router-http-port=8080
   --router-https-port=8443`). That's what DDEV's CI does for rootless Podman
   and socktainer, and what this run used.
2. `ddev config global --router-bind-all-interfaces`: 80/443 work, but the
   sites are then reachable from the network.
3. In Kiri: a privileged helper, or binding the wildcard address and
   refusing connections that don't come from loopback. Worth suggesting
   upstream, low priority.

**A trap:** DDEV's router publishes the ports of *every* running project on
the engine, whichever global config started it. With `d11` (80/443) still
running, a project started with the 8080/8443 config still failed with
`Permission denied`, because the router also asked for 127.0.0.1:80/443. After
`ddev stop d11` and setting `~/.ddev`'s ports to 8080/8443 too, it worked.

DDEV now explains this when it happens (2f098e9):
`Kiri on macOS can't publish ports below 1024 on 127.0.0.1. Use unprivileged router ports, …`.

## Step 2: #9167 on Homebrew Kiri

`scripts/ddev-smoke-test.sh` with DDEV 1fb3805, Mutagen (the macOS default):

```text
engine: Kiri 27.5.1 context=kiri
PASS ddev start (18s)
PASS http via router :8080
PASS https via router :8443 (mkcert CA)
PASS ddev exec
PASS web runs as host uid
PASS bind mount: host file visible
PASS bind mount: container file owned by host user
PASS mysql
PASS snapshot
PASS snapshot restore
PASS data back after restore
PASS export-db
PASS composer
PASS mailpit
PASS host.docker.internal resolves
PASS web container reaches host via host.docker.internal:25369
PASS ddev restart (15s)
PASS http after restart
SUMMARY pass=18 fail=0
```

A second project, `kpr2`, started while `kpr1` ran: 18/18, start 14s, and:

```text
Starting ddev-router, pushing config...
Container Recreated: ddev-router
Container Started: ddev-router
```

`kpr1` still answered afterwards (`smoke ok php 8.4.28`). In the web container:

```text
$ ddev exec ls -ln /usr/local/lib/ddev/mkcert
-rw------- 1 505 20 2484 Nov 22 17:29 rootCA-key.pem
-rw-r--r-- 1 505 20 1688 Nov 22 17:29 rootCA.pem
```

The same smoke test with main 85dcf05 (no #9167):

```text
FAIL ddev start
ERROR: failed to read the CA key: open /usr/local/lib/ddev/mkcert/rootCA-key.pem: permission denied
```

## Step 3: two projects share `db` (problem 6)

Two plain PHP projects, `kdns1` and `kdns2`, both running:

```text
== kdns1 web: getent ahostsv4 db / mysql -h db -e 'select @@hostname'
172.18.0.4
172.18.0.7
kdns1-db
ddev-kdns1_default=172.19.0.3 ddev_default=172.18.0.4
== kdns2 web
172.18.0.4
172.18.0.7
kdns1-db        <- kdns2's web is talking to kdns1's database
ddev-kdns2_default=172.20.0.3 ddev_default=172.18.0.7
```

Both answers are `ddev_default` addresses. DDEV puts every service on two
networks, the project's own `ddev-<name>_default` and the shared
`ddev_default`, and Compose gives each service its name as an alias on both.
So `db` is ambiguous on `ddev_default`. Docker's resolver tries a container's
networks one at a time and answers from the first that knows the name, and
that is the project network, so DDEV's `TestNetworkAmbiguity` (which checks
exactly this) passes on Docker in CI. On Kiri it fails:

```text
networks_test.go:137: "[172.18.0.4      test 172.18.0.9      test]" should have 1 item(s), but has 2
```

A plain-CLI check on Kiri shows it also answers from the first network only,
but "first" is the order the networks were listed in the create request:

```text
# t-aa on network aa with alias test; t-zz on network zz with alias test
docker run --network aa --network zz …  →  test = t-aa's address
docker run --network zz --network aa …  →  test = t-zz's address
```

So for DDEV's containers, Kiri treats `ddev_default` as the first network.
Docker wasn't available on this machine for a side-by-side run. What's
established is the DDEV test passing on Docker in CI, and failing here.

What it means: with two projects running, any service name (`db`, `web`,
`redis`, …) can resolve to the other project's container. Database writes can
land in the wrong project. #9167's router fallback makes it *possible* to run
two projects on Kiri; this makes it unsafe until Kiri fixes it.

## Step 4: other differences found by DDEV's tests

- **Problem 7, `docker volume rm -f` of a volume in use:**

  ```text
  $ docker run --name kvh -v kv:/mnt busybox sh -c 'echo data > /mnt/f'
  $ docker volume rm kv          → Error … volume is in use - [kvh]   (as Docker)
  $ docker volume rm -f kv       → kv, exit 0                        (Docker: still refused)
  $ docker volume ls -q | grep -c kv
  0
  ```

  (The volume and its data are gone. A check through `--volumes-from kvh`
  proves nothing on 0.2.2, because `--volumes-from` doesn't work there; see
  problem 11.)

  DDEV's `dockerutil.RemoveVolume()` uses `Force: true` and counts on the
  in-use error to tell the user which containers hold the volume
  (`TestRemoveVolumeInUseNamesContainer`). On Kiri, the data goes instead.
  Docker's `force` only means "no error if the volume doesn't exist".
- **Problem 8, a missing command:** `docker run busybox nocommandbythatname`
  on Kiri starts the container, which exits 127 with
  `kiri: cannot start container: nocommandbythatname: executable file not found in $PATH`.
  Docker fails the start request itself. DDEV still reports an error, with
  different wording (`TestRunSimpleContainer` expects `failed to start container`).
  Cosmetic.

## DDEV automated tests

Each run had `DOCKER_CONTEXT=kiri`, the 8080/8443 global config,
`GOTEST_SHORT=true` (one CMS per test), and nothing else on the engine.

The runner's environment sets `DDEV_RUN_TEST_ANYWAY=true`, which overrides
`GOTEST_SHORT`, so these were the **full** suites, including tests DDEV's CI
skips. "Kiri n" is the problem number in
[docs/kiri-fixes.md](../docs/kiri-fixes.md).

| Suite | Passed | Failed | Skipped | Time |
|---|---|---|---|---|
| `make testnotddevapp` (all of `pkg/` except `ddevapp`) | 261 | 4 | 10 | ~9 min of tests; `pkg/dockerutil` panicked partway (see below) |
| `pkg/dockerutil` alone, with the branch's 2f098e9 | 68 | 3 | 2 | 2.6 min |
| `pkg/ddevapp`, first run | 129 | 1 | 7 | 64 min, then the binary exited in `TestDdevAllDatabases` |
| `pkg/ddevapp`, the rest (everything that hadn't run) | 110 | 9 | 20 | 56 min |
| `make testcmd` (`cmd/ddev/cmd`) | 175 | 10 | 36 | 58 min |

(Top-level tests; the two `dockerutil` rows overlap.) About 680 tests
passed on Homebrew Kiri 0.2.2 with #9167. Every failure, by cause:

**Kiri (would fail for any DDEV user on 0.2.2):**

| Test | Cause |
|---|---|
| `pkg/dockerutil` `TestNetworkAmbiguity` | Kiri 6: `test` resolves to both projects' containers |
| `pkg/dockerutil` `TestRemoveVolumeInUseNamesContainer`, `pkg/ddevapp` `TestStopRemoveDataKeepsProjectListedWhenVolumeIsHeld` | Kiri 7: forced volume removal of a volume in use succeeds |
| `pkg/dockerutil` `TestRunSimpleContainer`, `cmd` `TestCmdExecTerminalChild` | Kiri 8: errors come back as output and exit codes, not API errors (cosmetic) |
| `cmd` `TestDeleteCmd`, `TestUtilityCheckCustomConfigCmd` | Kiri 10: image labels (fixed on Kiri main) |
| `cmd` `TestCmdAuthSSH`, `pkg/ddevapp` `TestSSHAuth` | Kiri 11: `--volumes-from` (fixed on Kiri main) |
| `cmd` `TestDebugMigrateDatabase`, `pkg/ddevapp` `TestDdevExportDB`, `TestWebserverMariaMySQLDBClient` (and `TestDdevAllDatabases` would) | Kiri 12: `mysql:8.4`/`9.7` have 75 layers; Kiri can't run more than 58 |
| `pkg/ddevapp` `TestRouterNotRebuiltOnHostnameChange`, `TestRouterPortSubstitutionPersistsAcrossProjects` | Kiri 5: the router is recreated instead of updated. Expected with #9167; the branch now skips the first on Kiri and lets the second accept a recreation. Rerun: the second **passes** (substitute ports survive the recreation), the first skips |

**DDEV, not Kiri:**

| Test | Cause |
|---|---|
| `pkg/ddevapp` `TestConfigValidate` | requested port 80 whatever the router port; fails on any provider run with 8080/8443. Fixed on the branch (bbe3b7a); passes on Kiri |
| `pkg/ddevapp` `TestDdevAllDatabases` (PostgreSQL 15) | snapshot restore can't write `/etc/postgresql/conf.d/recovery.conf` on macOS (gid 20 isn't the image user's group). Also reproduced by hand with `ddev snapshot restore`. Probably every macOS provider; see [ddev-side-notes](../docs/ddev-side-notes.md#found-by-running-ddevs-tests-on-kiri-not-kiri-problems). This ended the first `pkg/ddevapp` run |
| `pkg/ddevapp` `TestProcessHooks` | stale test: expects `Running task: …`, which DDEV now prints only at debug level as `=== Running task…`. CI skips it (`GOTEST_SHORT`); fails alone too |
| `cmd` `TestUtilityDiagnoseCmd/OutsideHomeDirectory` | test bug, only with `DDEV_TEST_OUTSIDE_HOME=true` |

**This machine or this run:**

| Test | Cause |
|---|---|
| `pkg/tui` `TestDashboardShowsProjects`, `TestSharedContainerHealth` | expect `DDEV v…`; the worktree build has no tags (`1fb3805`) |
| `pkg/amplitude` `TestInitAmplitudeAfterGlobalConfig` | Amplitude network check |
| `pkg/dockerutil` `TestGetContainerHealth` | my stray `cmd` `TestMain` run at the same time (see below); passed alone |
| `pkg/ddevapp` `TestListSnapshotRestoreTargetsWorktrees`, `TestResolveSnapshotRestoreTargetWorktrees` | `git commit` in test repos fails: this session's git config signs commits |
| `cmd` `TestShareCmdNgrok` | no ngrok auth token |
| `cmd` `TestDebugCdCmd` | lists `d11`, a project on the same engine from someone else's config |
| `cmd` `TestPoweroffOnNewVersion` | follow-on from `TestDeleteCmd`; **passes alone** |

**Unexplained:** `cmd` `TestDebugRebuildCmd`: `ddev xhgui on` after a series
of rebuilds timed out with xhgui stuck in `starting`, in both the full run and
a rerun. The same sequence by hand (custom web/db Dockerfiles, `rebuild`,
`rebuild --service db`, `rebuild --all --cache`, `restart`, `xhgui on`, also
with a 29-character project name) gave a healthy xhgui in under a second
every time.

## Plan deviations and incidents

- `d11` (someone's Drupal project on Kiri, default `~/.ddev`) was stopped with
  `ddev stop d11`, with the user's agreement, and `~/.ddev`'s global router
  ports were set to 8080/8443. Its data is kept. Start it again with
  `ddev start` in `~/workspace/d11`; it now gets 8080/8443.
- A compile check, `go test -run '^$' ./cmd/ddev/cmd`, isn't one: that
  package's `TestMain` sets up test sites (with whichever `ddev` is on `PATH`)
  even when no test matches. It ran for 11 minutes against Kiri, alongside the
  `testnotddevapp` run, before its timeout. It probably caused that run's
  `TestGetContainerHealth` failure (its test container had vanished), which
  passed when `pkg/dockerutil` was run again alone. Use `go vet` to
  compile-check `cmd/ddev/cmd`.
- The `rfay/ddev` checkout had stale untracked files under `vendor/` that
  stop it from compiling. They were left alone; the work used a separate
  worktree.
