Title: Images with more than 58 layers can't start: overlayfs mount options exceed one page

### What happened

Any container from an image with 59 or more layers fails to start. The
rootfs mount fails with `Invalid argument (os error 22)` or
`No such file or directory (os error 2)`. Docker runs the same images.

### Kiri version

0.2.2 (Homebrew cask, app opened normally), macOS 27.2.1 (26B131), Apple M1.
The code below is unchanged on main (d80976c), so this should affect every
platform.

### Reproduce

Needs only busybox. Builds images with 58, 59 and 75 layers (one `RUN` per
layer) and runs each:

```bash
#!/bin/bash
set -u
dir=$(mktemp -d)
for n in 58 59 75; do
  { echo 'FROM busybox:latest'; for i in $(seq 2 $n); do echo "RUN echo $i > /f$i"; done; } > "$dir/Dockerfile"
  docker build -q -t layers-test:$n "$dir" >/dev/null
  layers=$(docker image inspect -f '{{len .RootFS.Layers}}' layers-test:$n)
  if out=$(docker run --rm layers-test:$n true 2>&1); then echo "layers=$layers: runs"; else echo "layers=$layers: FAILS: $out" | head -1; fi
  docker rmi layers-test:$n >/dev/null
done
rm -rf "$dir"
```

On Kiri 0.2.2:

```text
layers=58: runs
layers=59: FAILS: docker: Error response from daemon: run ec38687ebeb9…: mount /var/lib/kiri/containers/ec38687ebeb9…/rootfs: Invalid argument (os error 22)
layers=75: FAILS: docker: Error response from daemon: run 17a172765dd0…: mount /var/lib/kiri/containers/17a172765dd0…/rootfs: No such file or directory (os error 2)
```

On Docker 29.8.2 (OrbStack), same Mac:

```text
layers=58: runs
layers=59: runs
layers=75: runs
```

Narrowing it down with more sizes: 40, 50, 52, 54, 55, 56 and 58 layers run;
59, 60, 61 and 70 fail.

### Why (as far as I can tell)

`crates/kiri-init/src/linux/container.rs`, `mount_rootfs`, makes one
overlayfs mount whose `lowerdir=` lists every layer by its 64-character hex
directory name (relative to the layer store, so about 65 bytes per layer
with the `:`), followed by the absolute `upperdir` and `workdir`. The
`mount(2)` data argument is limited to one page (4096 bytes). 58 × 65 = 3770
bytes plus the two paths fits; 59 × 65 = 3835 plus the paths doesn't.

Docker's overlay2 driver avoids this with short link names for the lower
directories (26-character ids under `l/`). Other options are `lowerdir+=`
one layer at a time through `fsconfig()` (Linux 6.8+), or merging layers
above some threshold.

### Impact

Real images hit this. DDEV's database images for MySQL 8.4 and 9.7
(`ddev/ddev-dbserver-mysql-8.4`, `-9.7`) have 75 layers, so those database
types can't run on Kiri at all. Found while testing DDEV on Kiri
(ddev/ddev#9167); the repro above doesn't involve DDEV.

---
Investigated and written up with help from Claude Code; the repros above were run on a real Mac and the outputs pasted as they came.
