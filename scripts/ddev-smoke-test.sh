#!/bin/bash
# DDEV smoke test against whatever Docker engine DOCKER_CONTEXT points at.
#
# Usage: scripts/ddev-smoke-test.sh <project dir> [project name]
# Environment:
#   DOCKER_CONTEXT        the engine to test (for example kiri)
#   DDEV_XDG_CONFIG_HOME  a DDEV global config dir of its own (see docs), so your
#                         normal DDEV projects and settings are left alone
#   ROUTER_IP             where the router's ports are reachable (default 127.0.0.1;
#                         the engine container's IP in the nested Linux setup)
#   PERFORMANCE_MODE      none or mutagen (default: DDEV's default for the OS)
# Needs jq, curl and python3 (for a throwaway HTTP server on the host).
# Prints PASS/FAIL per check and a summary; leaves the project running.
set -u
DIR=$1; NAME=${2:-kirismoke}; IP=${ROUTER_IP:-127.0.0.1}
PASS=0; FAIL=0
ok()   { echo "PASS $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL $1${2:+: $2}"; FAIL=$((FAIL+1)); }
check() { local name=$1 want=$2; shift 2; local got; got=$("$@" 2>&1); if [[ "$got" == *"$want"* ]]; then ok "$name"; else bad "$name" "$(echo "$got" | tail -3 | tr '\n' ' ')"; fi; }

echo "engine: $(docker version -f '{{.Server.Platform.Name}} {{.Server.Version}}' 2>&1) context=${DOCKER_CONTEXT:-default}"
mkdir -p "$DIR/web" && cd "$DIR" || exit 1
echo '<?php echo "smoke ok php ".PHP_VERSION;' > web/index.php
ddev config --project-name="$NAME" --docroot=web --project-type=php ${PERFORMANCE_MODE:+--performance-mode=$PERFORMANCE_MODE} >/dev/null || exit 1
START=$(date +%s)
if ddev start -y > ddev-start.log 2>&1; then ok "ddev start ($(( $(date +%s) - START ))s)"; else bad "ddev start" "see $DIR/ddev-start.log"; tail -20 ddev-start.log; exit 1; fi

HTTP=$(ddev describe -j | jq -r '.raw | "\(.router_http_port // "80") \(.router_https_port // "443") \(.mailpit_url // "")"')
read -r HP SP MP <<<"$HTTP"
H="$NAME.ddev.site"
CA="$(mkcert -CAROOT 2>/dev/null)/rootCA.pem"
check "http via router :$HP"  "smoke ok" curl -s -m 10 --resolve "$H:$HP:$IP" "http://$H:$HP/"
check "https via router :$SP (mkcert CA)" "smoke ok" curl -s -m 10 --cacert "$CA" --resolve "$H:$SP:$IP" "https://$H:$SP/"
check "ddev exec" "PHP" ddev exec php -v
check "web runs as host uid" "$(id -u)" ddev exec id -u
check "bind mount: host file visible" "index.php" ddev exec ls /var/www/html/web
ddev exec touch /var/www/html/from-container >/dev/null 2>&1
check "bind mount: container file owned by host user" "$(id -un)" ls -l from-container
rm -f from-container
check "mysql" "42" ddev mysql -N -e 'select 42'
ddev mysql -e 'create table if not exists smoke(i int); delete from smoke; insert into smoke values (7)' >/dev/null 2>&1
check "snapshot" "Created database snapshot" ddev snapshot --name smoke
ddev mysql -e 'drop table smoke' >/dev/null 2>&1
check "snapshot restore" "restored" ddev snapshot restore smoke
check "data back after restore" "7" ddev mysql -N -e 'select i from smoke'
check "export-db" "Wrote database dump" ddev export-db --file="$DIR/smoke.sql.gz"; rm -f "$DIR/smoke.sql.gz"
check "composer" "Composer version" ddev composer --version
check "mailpit" "200" curl -s -o /dev/null -w '%{http_code}' -m 10 --resolve "$H:${MP##*:}:$IP" "http://$H:${MP##*:}/"
check "host.docker.internal resolves" "." ddev exec getent hosts host.docker.internal
# Something listening on the host, reached from the web container (what Xdebug needs).
PORT=$(( 20000 + RANDOM % 20000 ))
python3 -m http.server "$PORT" --bind 0.0.0.0 >/dev/null 2>&1 & SRV=$!
sleep 1
check "web container reaches host via host.docker.internal:$PORT" "200" ddev exec curl -s -o /dev/null -w '%{http_code}' -m 5 "http://host.docker.internal:$PORT/"
kill $SRV 2>/dev/null
START=$(date +%s)
if ddev restart >/dev/null 2>&1; then ok "ddev restart ($(( $(date +%s) - START ))s)"; else bad "ddev restart"; fi
check "http after restart" "smoke ok" curl -s -m 10 --resolve "$H:$HP:$IP" "http://$H:$HP/"
echo "SUMMARY pass=$PASS fail=$FAIL (project $NAME left running; ddev delete -Oy $NAME to remove)"
[ $FAIL -eq 0 ]
