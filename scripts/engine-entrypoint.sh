#!/bin/sh
# Runs inside the Kiri engine container (see run-kiri-engine.sh).
apk add -q iptables nftables curl >/dev/null 2>&1
# A socket left from before a restart would get the chmod below instead of the new one.
rm -f /run/kiri/docker.sock
/opt/kiri/kiri daemon &
# The socket is created root-only; open it to the host user, whose directory it is in.
for i in $(seq 50); do
  if [ -S /run/kiri/docker.sock ]; then chmod 666 /run/kiri/docker.sock; break; fi
  sleep 0.2
done
wait
