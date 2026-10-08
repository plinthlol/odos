# odos — build plan (Wayland-only)

`odos` (ὁδός): path. Wayland-only terminal. Logo: `assets/logo-merge.svg`.

## What we reuse from rhun

- `src/plat/wayland.s:1-80` — native Wayland client, no libwayland (wire protocol over unix socket, shm buffers). This is the model for odos Wayland shell.
- `src/gfx/canvas.s`, `font.s`, `raster.s` — CPU raster + text, no GPU dependency.
- `src/ui/ui.s:2082` — immediate-mode widgets (tabs, scrollbar, search).
- `src/app/term.s:3288` — reference xterm VT (ground/esc/csi/osc state machine). Already works, proves asm VT is viable.
- `src/app/termview.s:3212` — grid -> pixels, selection, scrollback.
- `build.sh` — `as --64 + ld -static -nostdlib` pattern.

Wayland-only means delete: `src/plat/x11.s`, `src/win/*`, `src/mac/*`, XKB/Xcursor paths.

## What libghostty-vt gives us

- `libghostty-vt`: Zig + C library (`libghostty-vt.a` + `include/ghostty/vt/*.h`: `terminal.h`, `screen.h`, `grid_ref.h`, `style.h`, `allocator.h`, `device.h`, `modes.h`, `io.h`, `kitty_graphics.h`, `point.h`, `selection.h`, `size_report.h`, `types.h`). Parsing + terminal state + grid. No libc required, freestanding-capable by design.
- Status (2026): functionality stable (powers Ghostty GUI for years), **C API not stable** (`src/lib_vt.zig` warns signatures may change). Pin a commit hash.
- What it does NOT give: Wayland window, font shaping, GPU rendering. We still own all that (rhun side).

## Decision: 2 tracks, pick one for v0.1

### Track A — asm-native (recommended for v0.1)
Extend `src/app/term.s` VT directly. No Zig, no libc, keep `-nostdlib`.
- Pros: builds today, matches rhun style, smallest binary, no unstable API risk.
- Cons: you don't get Ghostty's full VT coverage for free.
- Use when: you want a working Wayland terminal fast.

### Track B — hybrid asm + libghostty-vt
Link `libghostty-vt.a` into asm via C-ABI shim. No libc required (you're right).
- Pros: best VT correctness (kitty graphics, unicode, modes).
- Cons: must build Zig freestanding (`os.tag == .freestanding`), provide custom `GhosttyAllocator` vtable mapping to `mem_alloc`/`mem_free` (default alloc fails on freestanding), provide `sys` callbacks via `ghostty_sys_set` + `TinyIo` for fs-touching paths, write asm->C thunks for `terminal.h` (create/feed/grid_ref), pin + track upstream API churn (API explicitly unstable).
- Use when: VT conformance > integration work.

Recommendation: **ship Track A v0.1, spike Track B in parallel**. Compare `vttest` / Ghostty conformance suite to decide if B is worth it.

## Phases

### 0. Skeleton (1 day) — DONE
- `odos/src/odos.s` + `odos/build.sh`: `_start` -> Wayland connect -> shm window -> merge-mark frame -> loop. Verified: links, graceful no-display exit.
- Note: rhun `build.sh:12` globs `find src`, so top-level `odos/` is never picked up — no collision risk; the split-repo question is about git hygiene, not build breakage.
- Exit criteria: `build.sh && ./build/odos` opens Wayland window, no crash on resize/close.

### 1. PTY + echo (2-3 days) — DONE headless, needs compositor check
- Reuse `proc.s`: `pty_open` (`/dev/ptmx` + `TIOCSPTLCK`/`TIOCGPTN`, `IUTF8` setup) + `proc_spawn` (`SYS_vfork` + `SYS_setsid` + exec) + `pty_resize` (`TIOCSWINSZ` ioctl — kernel then sends `SIGWINCH` to the fg child). Pump via `loop.s` `poll` (`loop_poll`), nonblock master fd. See `termview.s:869` for the resize call site.
- VT: full `term.s` linked (`term_new/feed/resize/row/key`), 16-color + 256-cube `tcolor` port, `cp_width`+`wide_ranges` ported (doc.s stays out).
- Render: per-cell `gfx_fill` + `face_glyph`/`gfx_mask`, bold/underline/strike, cursor block. Verified by `tests/phase1.sh`: shell spawn, `echo odos-phase1-ok` round-trip, `term_dump` cursor, offscreen `app_render` at 800x600.
- Copy added: `wide_ranges` table, `tcolor`/`cube` logic — keep in sync with upstream if Ghostty/Track-B changes the palette math.

### 2. VT core (1-2 weeks)
- Track A: harden `term.s` — ground/esc/csi/osc machine + full CSI dispatch table (`term.s:3225` `@/A-Z`, `Lcsi_*`), DEC private modes (`dec_mode`), SGR (`sgr():2168`), alt-screen (`TM_lines`/`TM_other` swap at :943). Fuzz + `vttest`.
- Track B spike: `zig build libghostty-vt.a` freestanding, C header import, `shim.s`: `odos_term_new/feed/get_grid/render_cells`, custom allocator -> `mem_alloc`, `sys_set` + `TinyIo`. Measure: binary size, frame latency, crash surface.
- Exit: `vttest`, `htop`, `tmux`, `helix` render correctly.

### 3. Rendering + input (1 week)
- `canvas.s` cell batching, damage rects, fractional scale (`wayland.s:74` `scale120`), cursor (block/bar + blink), selection + clipboard via `wl_data_device_manager` (`wayland.s:2072` `id_ddm`) + `selection` handling, scrollback + search (`palette.s` pattern).
- Kitty keyboard protocol (`g_key_base` in `term.s:29`) + IME stub.
- Exit: 60fps cat of large file, no tearing, copy/paste works in Sway/Hyprland/GNOME.

### 4. Chrome + config (3-4 days)
- Strip `app.s` chrome to: single window, tabs, no editor/explorer/git. Keep `config.s` + `theme.s` (reuse `runtime/themes/`).
- `odos.ini`: font, size, opacity, scrollback, keybinds.
- Exit: cold start <50ms, config reload without restart.

### 5. Harden + release
- Tests: copy `tests/term_test.s`, `cols_test.s` pattern for odos; reuse `src/plat/headless.s` offscreen framebuffer for scripted runs instead of requiring a compositor; add Wayland launch test only for compositor matrix.
- `tools/package` minimal tar + desktop file (reuse `assets/rhun.desktop` pattern, `tools/install.sh:22` installs `rhun.svg` icon).
- `tools/package` minimal tar + desktop file (reuse `assets/rhun.desktop`).
- Docs: keybinds, Ghostty-VT delta, Wayland compositor matrix.

## Open questions
1. A or B for VT? Default A unless B spike shows >20% conformance win for <2x complexity.
2. Font: reuse rhun path (`assets/fonts/IosevkaFixed-Regular.ttf` + `gfx/font.s` `face_init`/`text_draw`). fc-match/HarfBuzz would break `-nostdlib` purity — libc + dynamic link, so Track A stays without it.
3. GPU: stay CPU/SHM like rhun, or OpenGL later like Ghostty (OpenGL Linux / Metal macOS)? Stay SHM for v0.1.
4. Upstream: odos lives in `rhun/odos/` for now, or split repo? Git hygiene only — `build.sh:12` `find src` can't collide.

## Next action
Say `go phase 0` and I scaffold `odos/src/main.s + odos/build.sh` (Track A).
Say `go spike B` and I fetch pinned ghostty rev + dump `vt.h`/`terminal.h` API surface for the shim.
