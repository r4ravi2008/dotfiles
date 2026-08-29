# Herdr agent picker and annotate plugin

Shipped. Spec: `docs/superpowers/specs/2026-08-28-herdr-agents-plannotator-design.md`.

The first pass on this branch installed Chromium plus `official.browser` / `official.plannotator` and ran presenter `configure`. That path is gone. `plannotator annotate` still opens a browser. In Herdr, use herdr-annotate.

## What bootstrap does

- `herdr/config.toml`: agent picker `prefix+a`, previous/next `alt+shift+[` / `]`, focus `prefix+alt+1..9`, annotate remaps (`prefix+shift+a` / `c` / `p` / `y`, `prefix+m`)
- `packages.conf` `cli`: `bun` (not Chromium). `_fallback_bun` if brew/apt cannot
- Pin `dleen/herdr-agents` `74f8550a1008156f811b0bc8663ac251d9f3fcd6`
- Pin `plannotator/herdr-annotate` `fb93a1318f960792452cef6cde72a2c4f4591241` (plugin id `annotate`)
- Uninstall leftover `official.browser` / `official.plannotator`
- CWS copy of config.toml appends `new_cwd = "/workspace"` and `[ui] copy_on_select = false`
- `configure_plannotator_local_only` still forces share disabled
- Herdr `0.8.2`

## Check

```bash
herdr config check
herdr plugin list --plugin dleen.herdr-agents --json
herdr plugin list --plugin annotate --json
command -v bun
grep -E '^chromium[[:space:]]*\|' packages.conf && echo FAIL_chromium_still_listed
```

`official.browser` and `official.plannotator` should be absent. `prefix+shift+p` opens plannotator-tui in Herdr.
