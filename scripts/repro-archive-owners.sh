#!/bin/bash
# libracoder/kiri#594: does PUT /containers/{id}/archive (docker cp) keep the
# tar's owners, as Docker does? Usage: scripts/repro-archive-owners.sh <docker context>
# Docker and fixed Kiri print "1234 1235 600" then "key".
# Kiri before the fix prints "0 0 600" and "Permission denied".
set -u
export DOCKER_CONTEXT=$1
T=$(mktemp -d)
python3 -I -c 'import io,sys,tarfile
b=io.BytesIO(); t=tarfile.open(fileobj=b,mode="w"); f=tarfile.TarInfo("owned.pem"); f.size=3; f.mode=0o600; f.uid=1234; f.gid=1235
t.addfile(f,io.BytesIO(b"key")); t.close(); sys.stdout.buffer.write(b.getvalue())' > "$T/owned.tar"
docker run -d --name kiri-owner-repro alpine sleep 120 >/dev/null
docker cp - kiri-owner-repro:/tmp/ < "$T/owned.tar"
docker exec kiri-owner-repro stat -c '%u %g %a' /tmp/owned.pem
docker exec -u 1234 kiri-owner-repro cat /tmp/owned.pem; echo
docker container rm -f kiri-owner-repro >/dev/null
rm -f "$T/owned.tar"; rmdir "$T"
