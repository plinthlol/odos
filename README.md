# odos

A minimal but featureful terminal emulator.
`odos` (ὁδός) — path / way. Wayland-only.

## Plan

- UI/GPU: reuse from `../src/` — `ui/ui.s`, `gfx/canvas.s`, `gfx/font.s`, `plat/wayland.s`
- VT: libghostty (Zig) via C-ABI shim
- Wayland only: drop `plat/x11.s`, `mac/`, `win/`

## Dir

- `assets/logo.svg` — logo
- `src/` — TODO: shim + wayland shell
- `notes.md` — TODO: integration notes

## Next

1. Decide: link ghostty VT as static lib, or port `app/term.s` VT natively
2. Minimal Wayland window + `canvas.s` frame
3. PTY + VT feed-through
