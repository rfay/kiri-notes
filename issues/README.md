# Draft issues for libracoder/kiri

Each file is a complete issue: a title line, then the body. Every repro uses
only the `docker` CLI and busybox, and shows both Kiri's and Docker's output
from the same Mac (Kiri 0.2.2, OrbStack 2.2.5 with Docker 29.8.2; Colima with
Docker 29.5.2 for the DNS one). Sessions working from this repository can't
post to `libracoder/kiri`, so post them from your own shell. Kiri's
CONTRIBUTING asks for its bug form and disclosure of AI use; adjust as needed.

| File | Problem | Status (2026-11-23) |
|---|---|---|
| [01-layer-limit.md](01-layer-limit.md) | 12: images with more than 58 layers can't start | **not posted**: already fixed on Kiri main (a3b8ff0, libracoder/kiri#682) |
| [02-volume-rm-force.md](02-volume-rm-force.md) | 7: `volume rm --force` removes a volume in use | **posted**: [libracoder/kiri#773](https://github.com/libracoder/kiri/issues/773) |
| [03-dns-network-order.md](03-dns-network-order.md) | 6: multi-network DNS answers from a different network than Docker | **not posted**: duplicate of [libracoder/kiri#294](https://github.com/libracoder/kiri/issues/294), fixed on Kiri main by #581 |

To post one (title from the first line, body from the rest):

```bash
f=issues/01-layer-limit.md; gh issue create --repo libracoder/kiri --title "$(head -1 "$f" | sed 's/^Title: //')" --body "$(tail -n +3 "$f")"
```
