# third_party

Managed by `../build.sh` — nothing here is committed except this README
and `ghost_probe.c` (ABI reference for `src/vt_*.s`).

On first build, `build.sh` fetches:

- Zig >= 0.16 (system, else a local tarball under `third_party/`)
- ghostty @ pinned rev (see `GHOSTTY_REV` in `build.sh`), then builds
  `ghostty/zig-out/lib/libghostty-vt.a` freestanding + ReleaseFast

To inspect the C ABI:

```sh
gcc -I ghostty/include -o /tmp/probe ghost_probe.c && /tmp/probe
```
