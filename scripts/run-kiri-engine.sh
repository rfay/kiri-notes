#!/bin/bash
# Run Kiri's Linux engine in a privileged container on an existing Docker daemon,
# the way Kiri's own tests/linux-host.sh does, and create a docker context for it.
#
# Usage: scripts/run-kiri-engine.sh <dir with kiri and kiri-init> <work dir> [name]
#
# - The engine gets its own network namespace, so it can't touch the host's
#   firewall rules; its published ports live on the engine container's IP
#   (printed at the end), not on the host's localhost.
# - <work dir> is mounted at the same path inside, so DDEV projects under it
#   can be bind-mounted. Put your DDEV projects and DDEV_XDG_CONFIG_HOME there.
# - /run is a tmpfs, as in Kiri's tests/linux-host.sh. The daemon makes
#   /run/kiri-agent-<pid>-<n> for each agent start and leaves it behind when it
#   is killed; with a persistent /run, a restarted engine container (where the
#   daemon often gets the same pid) fails with "VM did not boot: File exists".
set -eu
BIN=$(cd "$1" && pwd); WORK=$(mkdir -p "$2" && cd "$2" && pwd); NAME=${3:-kiri-engine}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$WORK/run"
rm -f "$WORK/run/docker.sock"   # from an earlier engine; the wait below must see the new one
MOUNTS=(-v "$WORK:$WORK")
CAROOT=$(mkcert -CAROOT 2>/dev/null || true)
[ -n "$CAROOT" ] && [ -d "$CAROOT" ] && MOUNTS+=(-v "$CAROOT:$CAROOT:ro")
[ -n "${SSH_AUTH_SOCK:-}" ] && MOUNTS+=(-v "$(dirname "$SSH_AUTH_SOCK"):$(dirname "$SSH_AUTH_SOCK")")
docker run -d --name "$NAME" --privileged --cgroupns private --tmpfs /tmp --tmpfs /run \
  -e KIRI_SOCKET=/run/kiri/docker.sock -e HOME=/var/lib/kiri-daemon \
  -v "$WORK/run":/run/kiri -v "$NAME-data":/var/lib/kiri -v "$NAME-home":/var/lib/kiri-daemon \
  -v "$BIN":/opt/kiri:ro -v "$HERE/engine-entrypoint.sh":/entrypoint.sh:ro "${MOUNTS[@]}" \
  alpine /entrypoint.sh >/dev/null
docker context inspect "$NAME" >/dev/null 2>&1 || docker context create "$NAME" --docker host="unix://$WORK/run/docker.sock" >/dev/null
for _ in $(seq 60); do docker --context "$NAME" version >/dev/null 2>&1 && break; sleep 1; done
docker --context "$NAME" version --format 'Kiri engine: {{.Server.Platform.Name}} API {{.Server.APIVersion}}'
echo "Engine IP (published ports are here): $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$NAME")"
