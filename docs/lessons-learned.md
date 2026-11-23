# Lessons learned (read before testing)

What the Linux evaluation (2026-11-19/20) found the hard way, so the next run
doesn't have to rediscover it. Each item says what you'll see and what it means.
Platform-specific items are marked.

## Reading failures

| What you see | What it is | What to do |
|---|---|---|
| `ddev start` builds and starts containers, then `Failed waiting for web/db containers… web container exited`; `ddev logs -s web` ends with `mkcert -install` / `ERROR: failed to read the CA key: open /usr/local/lib/ddev/mkcert/rootCA-key.pem: permission denied` | Kiri bug #594: files copied into a container become root's | Expected on Kiri without #595. Use the fixed Kiri or the DDEV workaround branch |
| `ddev-router already running, pushing new config...` then `failed to update router network aliases: failed to disconnect container … Kiri cannot disconnect a running container from its first network (ddev_default); stop the container first` (on a Mac with Kiri 0.2.2: `… Kiri cannot disconnect a container from its first network (ddev_default)`) | Problem 5: Kiri refuses `network disconnect` on a running container's first network | Expected when a second project starts while one runs, with released DDEV. Stop the other projects, or use the DDEV workaround branch (it recreates the router instead) |
| Problem 5 again, though no other project is running | The router outlives stopped projects (and a failed start leaves its project running). Any start that changes the router's aliases (a different project) hits problem 5 | With released DDEV, remove the router first: `ddev poweroff` with Kiri's `DOCKER_CONTEXT` and `DDEV_XDG_CONFIG_HOME`. `ddev restart` of the same project is fine |
| Kiri's log: `the VM's NAT network is still unreachable; published ports keep going over vsock … No route to host (os error 65)` | macOS Local Network privacy blocks the engine from the VM's NAT address (as it blocks Apple's container runtime on unattended Macs) | Harmless for DDEV: Kiri falls back to vsock and published ports work. Allow the prompt on the desktop if one appears |
| `ddev-router is running, but nothing answers on host port(s) …` | DDEV checks the ports on the host's localhost | Linux nested: expected, because the ports are on the engine container's IP. **macOS: a real failure**, meaning Kiri isn't forwarding the ports to localhost. Record it |
| `kiri: cannot start container: mount: mknod dev/null: Operation not permitted`, `ulimits: error setting rlimit type 7`, or `stdio: No such file or directory` | Problems 2 and 3: Kiri itself is running inside a user namespace | Linux nested only. Not expected on a Mac, where Kiri has its own VM |
| `VM did not boot: File exists (os error 17)` after restarting a Linux engine container | Leftover `/run/kiri-agent-<pid>-<n>` directories in a persistent `/run` | Linux nested only, and fixed in `scripts/run-kiri-engine.sh` (`--tmpfs /run`) |
| `web container reaches host via host.docker.internal` fails | In the nested setup that name points inside Kiri's own network namespace | Linux nested: expected. **macOS: a real failure** (Xdebug won't connect). Record what `ddev exec getent hosts host.docker.internal` returns |

| A released DDEV (v1.25.5) passes everything on released Kiri, though the repro shows #594 | v1.25.5 keeps the mkcert CA in the `ddev-global-cache` volume and never copies it into the container. Only DDEV main after v1.25.5 copies it with `docker cp` | Not a contradiction. The Linux "released DDEV" runs used v1.25.5-87 from main. Say which DDEV you ran |
| `ls ~/Kiri` or `ls ~/"Kiri Ddev"` hangs; Kiri's e2e suite stalls in "container files in Finder" | macOS: the Finder NFS mount is present but nothing answers. Seen with engines started by hand with `kiri daemon` (2026-11-20) | Record it, and run the suite with that section disabled (see the plan, step 6) |
| e2e `host-net` fails: wants `192.168.64.`, gets `192.168.65.x` | macOS: another Virtualization.framework VM already uses 192.168.64.0/24 | Environmental, on every Kiri build |
| Router `Exited (137)`; Kiri's log: `ports not published; container stopped … Permission denied (os error 13)` | macOS: Kiri can't publish ports below 1024 on 127.0.0.1 (problem 9) | `ddev config global --router-http-port=8080 --router-https-port=8443`, and stop any running project that still uses 80/443 |
| `mount /var/lib/kiri/containers/<id>/rootfs: No such file or directory` (or `Invalid argument`) on start | The image has more than 58 layers (problem 12), e.g. DDEV's `mysql:8.4`/`mysql:9.7` | Use another database type; check with `docker image inspect -f '{{len .RootFS.Layers}}'` |
| `ddev auth ssh`: `Error connecting to agent: No such file or directory` | Kiri 0.2.2's `--volumes-from` mounts nothing (problem 11) | `ddev auth ssh -f <keyfile>` |
| `db` in one project's web container answers from another project | Kiri's multi-network name resolution (problem 6) | Run one project at a time |

## Facts about Kiri that matter to DDEV

- **Identity:** `docker info` says `OperatingSystem: Kiri`, `Name: kiri`,
  `Runtimes: kiri`. `docker version` says `Platform.Name: Kiri`, Engine `27.5.1`,
  API `1.47`, plus a `Kiri` component with the real version. DDEV has no
  `IsKiri()`, so it treats Kiri as generic Docker.
- **Builds:** for a non-Docker-Desktop context, buildx creates
  `buildx_buildkit_default` (a privileged `moby/buildkit` container, restart
  policy `unless-stopped`) on the first build. The first `ddev start` then takes
  about 35 s longer while it pulls and boots; later builds take under 5 s.
  Leave that container alone. Kiri brings it back when the engine restarts.
- **`docker cp` / archive uploads:** Docker keeps the uid/gid from the tar
  headers **even without `-a`**, whatever its docs suggest; `-a`
  (`copyUIDGID`) gives the files to the container's user instead. Kiri
  without #595 makes root the owner unless `copyUIDGID` is set, and when it
  is set, Kiri keeps the tar's owners. The DDEV workaround branch relies on
  that.
- **Networks:** a *stopped* container can leave its first network (Kiri
  #418/#584). A *running* one can't (problem 5). Other networks connect and
  disconnect normally.
- **Ports Kiri claims for itself:** the engine serves HTTPS for
  `*.kiri.localhost` / `*.kiri.local` on 443. On a Mac the app holds host
  ports 80 and 443 when "domains" are on, and DDEV's router wants the same
  ports. Turn the domains off, or use the alternate router ports in the plan.
  The released engine (`kiri daemon`) binds `*:80` and `*:443` even when
  another provider (OrbStack) holds them on localhost. `KIRI_HTTP_PORT` and
  `KIRI_HTTPS_PORT` move them. A dev flavor (`app-dev`) starts no routers.
- **Running without the app (macOS):** `/Applications/Kiri.app/Contents/MacOS/kiri daemon`
  serves `~/.kiri/run/docker.sock`; a dev flavor's binary serves
  `~/.kiri-<flavor>/run/docker.sock`. Neither creates a docker context then:
  `docker context create kiri --docker host=unix://$HOME/.kiri/run/docker.sock`.
  `kiri version` is docker's `version`, and the Kiri version is the `Kiri`
  component in `docker version` (a dev build says `0.0.0`). A released and a
  dev engine run side by side without trouble.
- **Building #595's guest on a Mac:** the fix is in the initramfs only. The
  released app's `Contents/Resources/guest/Image` and `data.img.tgz` can stand
  in for `cargo xtask kernel` / `disk`. `cargo xtask guest` needs the
  `aarch64-unknown-linux-musl` Rust target and a Docker engine (the released
  Kiri works).
- **`host.docker.internal`:** built in. On a Mac, Kiri's documented host
  gateway is `198.19.248.254`. DDEV adds no `extra_hosts` on macOS for a
  generic provider, so Xdebug depends on Kiri's built-in name.
- **Logs:** on a Mac, `~/.kiri/logs/` holds `daemon.log` (JSON lines),
  `guest-console.log` and `cli.log`. A dev build started by hand logs to its
  stderr instead. On Linux it's the daemon's stderr.
- **Kiri's e2e suite** takes about 7–9 minutes per engine on an M1 once the
  images are pulled. Run against a release, it fails dozens of checks for
  features newer than the release; compare like with like.
- **Kiri's e2e suite** (`tests/e2e.sh`) can't run a single section. It uses
  `DOCKER_CONTEXT` to choose the engine and derives a feature name from it (a
  context `kiri-ddev` is "Kiri Ddev", with a Finder folder `~/Kiri Ddev`). It
  needs `perl`, `python3` and `curl`, and only removes what it created.
- **Kiri's own rustfmt/clippy** report findings on main with a current
  toolchain. Compare a branch against main, not against zero.

## DDEV tooling details

- Every command against Kiri needs `DOCKER_CONTEXT` **and** a DDEV global
  config of its own (`DDEV_XDG_CONFIG_HOME`); otherwise DDEV's project list
  and router settings mix with the normal provider's. With both a normal
  `~/.ddev` and a custom one, DDEV prints
  `Warning: multiple global DDEV configurations found … is in use`. That's
  expected; ignore it.
- `ddev config global` has flags for the router, Mailpit and Traefik monitor
  ports, but **not for XHGui**. Edit `global_config.yaml` for those if needed.
- `ddev describe -j | jq '.raw'` gives `router_http_port`,
  `router_https_port` and `mailpit_url`. The smoke test uses them.
- `make` in a ddev checkout writes to `.gotmp/bin/<os>_<arch>/ddev`. If that
  directory is already on `PATH`, the new build shadows the installed `ddev`
  without your noticing. Run `ddev --version` before each test and record it.
  (One Linux "control" run accidentally used the workaround build this way.)
- `ddev delete -Oy <name>` needs the same `DOCKER_CONTEXT` and
  `DDEV_XDG_CONFIG_HOME` as the project was started with.
- DDEV's router publishes the ports of **every** running DDEV project on the
  engine, whichever global config started it. A project someone else started
  with 80/443 on the same Kiri makes your router fail too. Check
  `docker ps` on the Kiri context first.
- Running DDEV's tests against Kiri: set `DOCKER_CONTEXT=kiri` and a
  `DDEV_XDG_CONFIG_HOME` whose global config uses 8080/8443 (the tests copy the
  router ports from it). Nothing else may use the engine meanwhile: the tests
  power off and delete projects.
- This runner's environment sets `DDEV_RUN_TEST_ANYWAY=true` (and
  `DDEV_TEST_OUTSIDE_HOME`, `DDEV_TEST_SHARE_CMD`), which **overrides
  `GOTEST_SHORT`**: the full suites run. `pkg/ddevapp` took about 65 minutes and
  `cmd/ddev/cmd` about 58 on Kiri (M1).
- `go test -run '^$' ./cmd/ddev/cmd` is **not** a compile check there: the
  package's `TestMain` sets up test sites with whatever `ddev` is on `PATH`,
  against the current docker context. Use `go vet ./cmd/ddev/cmd`.
- Through `make`, `TESTARGS` goes into a `bash -c` string: `$` is expanded by
  make, and parentheses need quoting. `TESTARGS="-run 'TestA|TestB'"` works;
  anchors with `$` don't.
- A failure in DDEV's start path can end the whole `pkg/ddevapp` test binary
  (it exits the process), and every later test in the package doesn't run.
  Check the last `=== RUN` before trusting the totals.

## Process

- Sessions can't attach `libracoder/kiri` (refused). The `gh` on a session's
  PATH is a wrapper (`…/ccr/bin/gh`) that goes through the session's GitHub
  proxy, which reaches only attached repositories. Randy's own login is in
  the real `/opt/homebrew/bin/gh`. Use that for `libracoder/kiri` **only when
  Randy says so** in the conversation (he did on 2026-11-23, to post #773 and
  open #781); otherwise write drafts (as in `issues/`) for him to post.
- **Search Kiri's issues and its current main before filing.** Kiri moves
  fast: on 2026-11-23 two of three drafted issues (DNS order, more than 58
  layers) were already fixed on main, after 0.2.2. The local `rfay/kiri`
  checkout was days behind; fetch `https://github.com/libracoder/kiri main`.
- Kiri requires signed commits and a CLA. Commits for Kiri are authored as
  `Randy Fay <randy@randyfay.com>` and signed with his SSH key. Sessions can't
  sign with it: the session signing key file is empty, and no agent is
  reachable. Workflow that worked for #781: commit with
  `git -c commit.gpgsign=false commit --author 'Randy Fay <randy@randyfay.com>'`,
  push to `rfay/kiri`, and have Randy run `git commit --amend --no-edit -S` and
  `git push --force-with-lease`. Check `.commit.verification.verified` with
  `gh api repos/rfay/kiri/commits/<sha>` and that the tree is unchanged before
  opening the PR. Don't amend or force-push a branch Randy has signed.
- No Rust toolchain on the Mac runner now. Build and test Kiri in a container
  on OrbStack: `rust:1` (Debian), **not** `rust:1-alpine` (its musl toolchain
  can't link proc-macros: `unable to find library -lgcc_s`). The `kiri` crate
  is a binary: `cargo test -p kiri --bin kiri <filter>`. CI's unit tests are
  `cargo test --workspace --exclude kiri-init --locked`; CI runs no fmt or
  clippy, and both report findings on main, so compare a branch with main.
- DDEV test runs on this runner: `DDEV_RUN_TEST_ANYWAY=true` makes some tests
  very long (`TestDdevImportDB` 34 minutes on every database type). A
  background command is stopped after 2 hours, so run long suites detached
  (`nohup script &`) and watch their logs.
- Kiri's CONTRIBUTING wants an issue, and agreement, before any non-trivial PR,
  before/after output from a real machine, and AI use disclosed in the PR template.
