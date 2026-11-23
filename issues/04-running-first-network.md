Title: A running container can't leave its first network, so its network aliases can't be changed (follow-up to #418)

### What happened

`docker network disconnect` of a **running** container from its first network is refused. Docker allows it. #584 (for #418) fixed this for created and stopped containers, and its closing comment on #418 notes that a running container is still refused and needs "a separate change". I couldn't find an issue for that part, so here is one, with a use case.

The common reason to do this on a running container is to change its network aliases. Docker has no "update aliases" call, and `docker network connect` on an already-connected container fails with "endpoint … already exists". So the way to give a running container new aliases is to disconnect it and connect it again at once with the new alias list. On Kiri the first step fails, so the aliases can't be changed without stopping or recreating the container.

### Kiri version

0.2.2 (Homebrew cask, app opened normally), macOS 27.2.1 (26B131), Apple M1. Still the case on main (5fa739a): `crates/kiri/src/daemon/engine.rs`, `disconnect`, returns "Kiri cannot disconnect a running container from its first network (…); stop the container first". 0.2.2's message is shorter, as below.

### Reproduce

```bash
#!/bin/bash
set -u
docker network create alias-test-net >/dev/null
docker run -d --name alias-test-router --network alias-test-net --network-alias old-name busybox:latest sleep 300 >/dev/null
docker run -d --name alias-test-client --network alias-test-net busybox:latest sleep 300 >/dev/null
echo "+ docker network disconnect alias-test-net alias-test-router"
docker network disconnect alias-test-net alias-test-router; echo "exit=$?"
echo "+ docker network connect --alias old-name --alias new-name alias-test-net alias-test-router"
docker network connect --alias old-name --alias new-name alias-test-net alias-test-router; echo "exit=$?"
echo "+ aliases"
docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.Aliases}}{{end}}' alias-test-router
echo "+ docker exec alias-test-client nslookup -type=a new-name"
docker exec alias-test-client nslookup -type=a new-name 2>&1 | grep -E '^(Name|Address: [0-9])|can.t find|NXDOMAIN'
docker rm -f alias-test-router alias-test-client >/dev/null; docker network rm alias-test-net >/dev/null
```

On Kiri 0.2.2:

```text
+ docker network disconnect alias-test-net alias-test-router
Error response from daemon: Kiri cannot disconnect a container from its first network (alias-test-net)
exit=1
+ docker network connect --alias old-name --alias new-name alias-test-net alias-test-router
Error response from daemon: endpoint with name alias-test-router already exists in network alias-test-net
exit=1
+ aliases
alias-test-net [old-name]
+ docker exec alias-test-client nslookup -type=a new-name
** server can't find new-name: NXDOMAIN
```

On Docker 29.8.2 (OrbStack), same Mac:

```text
+ docker network disconnect alias-test-net alias-test-router
exit=0
+ docker network connect --alias old-name --alias new-name alias-test-net alias-test-router
exit=0
+ aliases
alias-test-net [old-name new-name]
+ docker exec alias-test-client nslookup -type=a new-name
Name:	new-name
Address: 192.168.107.2
```

### Impact

DDEV's router container is on one network, the shared `ddev_default`, with one alias per project hostname. When a project starts with new hostnames, DDEV updates the running router's aliases in place by exactly this disconnect and reconnect (`UpdateContainerNetworkAliases` in `pkg/dockerutil/containers.go`). On Kiri that fails, so with released DDEV a second project can't start while another runs. The router also outlives stopped projects, so even starting a different single project fails until the router is removed.

DDEV may fall back to recreating the router when the in-place update fails (ddev/ddev#9167). That works on Kiri, but recreating the router interrupts every running project's HTTP(S) for a moment, and other tools that update aliases this way have no fallback.

### Suggested fix

Allow a running container to leave its first network, as Docker does. #418's comment explains why that's harder (the default route and resolver live on the first network). If the general case is a big change, the narrow case may be enough for most users: a disconnect followed at once by a connect of the same container to the same network, which keeps the route and resolver on that network and only changes the endpoint's aliases.

---
Investigated and written up with help from Claude Code; the repro above was run on a real Mac and the outputs are copied from that run.
