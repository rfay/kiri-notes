Title: Embedded DNS on a multi-network container answers from a different network than Docker, so Compose projects reach each other's services

### What happened

A container on two networks asks the embedded DNS for a name that exists on
both. Docker answers from the container's networks **in network-name order**,
returning the matches on the first network that has the name. Kiri answers
from the network that was **listed first when the container was created**.

That matters for a common Compose layout: each project on its own network,
plus one shared network for a proxy, where every service is on both. Compose
gives each service its name as an alias on every network it joins, so `db` is
ambiguous on the shared network. On Docker, a project whose network name sorts
before the shared network's gets its own `db`. On Kiri, a service can get
**another project's `db`**.

### Kiri version

0.2.2 (Homebrew cask, app opened normally), macOS 27.2.1 (26B131), Apple M1.

### Reproduce

Two "projects", each with its own network and a `db` that has the alias `db`
on its own network and on a shared one. `web1` is on project 1's network and
the shared one. The shared network is created first, and listed first for
`web1`, so neither creation order nor request order favours the project
network; only the names do (`p1net` sorts before `shared`).

```bash
#!/bin/bash
set -u
R=$RANDOM
docker network create shared$R >/dev/null
docker network create p1net$R >/dev/null
docker network create p2net$R >/dev/null
for p in 1 2; do
  docker run -d --name db$p-$R --network name=p${p}net$R,alias=db --network name=shared$R,alias=db busybox:latest sleep 300 >/dev/null
done
docker run -d --name web1-$R --network shared$R --network p1net$R busybox:latest sleep 300 >/dev/null
for p in 1 2; do echo "db$p: $(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}' db$p-$R | sed "s/$R//g")"; done
echo "from web1, db resolves to: $(docker exec web1-$R nslookup -type=a db 2>/dev/null | awk '/^Address/ && !/#53|:53$/ {print $2}' | tr '\n' ' ')"
docker rm -f db1-$R db2-$R web1-$R >/dev/null; docker network rm shared$R p1net$R p2net$R >/dev/null
```

| Engine | `db` from web1 |
|---|---|
| Docker 29.8.2 (OrbStack) | `192.168.117.2`: db1 on `p1net` only |
| Docker 29.5.2 (Colima) | `172.19.0.2`: db1 on `p1net` only |
| **Kiri 0.2.2** | **`172.19.0.2 172.19.0.3`: db1 and db2, both on `shared`** |

Variations, to show the two rules:

| Setup | Docker (OrbStack and Colima) | Kiri 0.2.2 |
|---|---|---|
| As above (`p1net`, `shared`; `web1` lists `shared` first) | p1net's db1 | shared's db1 and db2 |
| `web1` lists `p1net` first | p1net's db1 | p1net's db1 |
| Renamed so the shared network sorts first (`a-shared`, `z-p1net`, `z-p2net`) | **a-shared's db1 and db2** | a-shared's db1 and db2 |
| Two networks `aa`, `zz`, one container with alias `test` on each; a querier on both | `aa`'s container, whichever order the querier lists them | the first network the querier lists |

So Docker doesn't isolate names by network either; it resolves in network-name
order, and Compose projects that rely on that (whether they know it or not)
get their own services. Kiri follows the create request's order.

### Impact

Found with DDEV (ddev/ddev#9167): every project's services are on
`ddev-<project>_default` and the shared `ddev_default`, and
`ddev-<project>_default` sorts before `ddev_default` (`-` before `_`). With two
projects running on Kiri, `db` in one project's web container resolved to both
projects' databases, and `mysql -h db` from the second project connected to
the **first** project's database. On Docker (OrbStack, same Mac) each project
reaches only its own. So on Kiri, writes can silently go to the wrong
project's database. The repro above doesn't involve DDEV or Compose.

### Suggested fix

Resolve over a container's networks in the same order Docker uses (by network
name), returning all matches from the first network that has the name.
