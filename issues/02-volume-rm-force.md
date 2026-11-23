Title: `docker volume rm --force` removes a volume that a container still uses

### What happened

`docker volume rm` of a volume that a (stopped) container uses is refused, as
on Docker. With `--force`, Kiri removes it, and its data is gone. Docker
refuses that too.

### Kiri version

0.2.2 (Homebrew cask, app opened normally), macOS 27.2.1 (26B131), Apple M1.

### Reproduce

```bash
#!/bin/bash
set -u
docker volume create vol-in-use-test >/dev/null
docker run --name vol-holder-test -v vol-in-use-test:/data busybox:latest sh -c 'echo important > /data/file'
echo "+ docker volume rm vol-in-use-test"
docker volume rm vol-in-use-test; echo "exit=$?"
echo "+ docker volume rm --force vol-in-use-test"
docker volume rm --force vol-in-use-test; echo "exit=$?"
echo "+ docker volume ls -q --filter name=vol-in-use-test"
docker volume ls -q --filter name=vol-in-use-test
docker rm -f vol-holder-test >/dev/null; docker volume rm vol-in-use-test >/dev/null 2>&1; true
```

On Kiri 0.2.2:

```text
+ docker volume rm vol-in-use-test
Error response from daemon: remove vol-in-use-test: volume is in use - [vol-holder-test]
exit=1
+ docker volume rm --force vol-in-use-test
vol-in-use-test
exit=0
+ docker volume ls -q --filter name=vol-in-use-test
```

(The volume, and the file in it, are gone.)

On Docker 29.8.2 (OrbStack), same Mac:

```text
+ docker volume rm vol-in-use-test
Error response from daemon: remove vol-in-use-test: volume is in use - [4b0374c90d5b…]
exit=1
+ docker volume rm --force vol-in-use-test
Error response from daemon: remove vol-in-use-test: volume is in use - [4b0374c90d5b…]
exit=1
+ docker volume ls -q --filter name=vol-in-use-test
vol-in-use-test
```

So on Docker, `force` doesn't override the in-use check (it lets a removal
go ahead despite other errors, such as a missing volume).

### Impact

Data loss. Tools pass `force` expecting Docker's behaviour. DDEV's volume
removal always sets `Force: true` and relies on the in-use refusal to stop and
tell the user which containers hold the volume; on Kiri the volume is removed
instead. Found while testing DDEV on Kiri (ddev/ddev#9167); the repro above
doesn't involve DDEV.

---
Investigated and written up with help from Claude Code; the repros above were run on a real Mac and the outputs pasted as they came.
