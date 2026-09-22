# videowall

Looping video wallpaper for Hyprland that **pauses itself while you play**.

`mpvpaper` plays your wallpaper video on loop; a small daemon listens to
Hyprland's event socket and **SIGSTOPs** `mpvpaper` the moment any window goes
fullscreen (games). While stopped, the wallpaper consumes **~0% CPU/GPU**.
When fullscreen ends, the wallpaper is resumed with SIGCONT.

Works on **standard Hyprland** and on the **Lua-config fork** (`_hlg_` builds).

## Quick path

1. Install the dependencies: `mpvpaper`, `ffmpeg`, `socat`, `hyprctl`.
   - Arch Linux: `sudo pacman -S ffmpeg socat` (`hyprctl` ships with Hyprland).
   - `mpvpaper`: AUR (`yay -S mpvpaper`) or build from
     [github.com/GianniCarlo/mpvpaper](https://github.com/GianniCarlo/mpvpaper).
   - Prefer `ffmpeg` for the automatic 1080p copy; without it the source is
     played as-is.
2. Run the installer **as your normal user** (never sudo):
   ```bash
   bash install.sh
   ```
3. Point the config at your video:
   ```bash
   $EDITOR ~/.config/videowall/videowall.conf   # set VIDEO= to a wallpaper file
   ```
4. Restart Hyprland — the wallpaper and the autopause daemon start with the
   session. To test without restarting:
   ```bash
   bash ~/.local/share/videowall/videowall &
   bash ~/.local/share/videowall/videowall-autopause &
   ```

The installer detects your Hyprland variant and wires autostart accordingly
(marker-based, idempotent — re-running it is safe).

## Configuration

`~/.config/videowall/videowall.conf` (created on first install, never
overwritten afterwards):

| Key | Default | Purpose |
|-----|---------|---------|
| `VIDEO` | — (required) | Absolute path to your wallpaper video. |
| `MONITOR` | `ALL` | `ALL`, or a single monitor name from `hyprctl monitors -j`. |
| `MPV_OPTS` | *(empty)* | Extra mpv options appended to the default set. |
| `WALLPAPER_DIR` | `~/.local/share/wallpapers` | Where the generated 1080p faststart copy is stored. |

## What it does

| Component | Installed to | Role |
|-----------|--------------|------|
| `videowall` | `~/.local/share/videowall/videowall` | Launcher: waits for monitors (bounded ~5 s, no blind sleep), generates a local 1080p faststart copy when stale, `pkill -x mpvpaper`, then `exec mpvpaper --loop-file=inf --no-audio --panscan=1.0`. |
| `videowall-autopause` | `~/.local/share/videowall/videowall-autopause` | Daemon: any socket event → re-check `hyprctl activewindow -j`; fullscreen → SIGSTOP, ended → SIGCONT. Idempotent, reconnects on socket drop, logs to `$XDG_RUNTIME_DIR/videowall-autopause.log`. |
| `videowall-picker` | `~/.local/share/videowall/videowall-picker` | TUI wallpaper picker: browse videos with size/resolution/duration, preview frames, apply live without restarting (see [Picker](#picker)). |
| Autostart | variant-dependent | fork: `hl.exec_cmd(...)` blocks inside `hl.on("hyprland.start", ...)` in `execs.lua`; standard: `exec-once =` lines in `hyprland.conf`. |

Why a local 1080p copy? The monitor is 1920x1080, so a 4K source is downscaled
anyway. The 1080p faststart copy opens in ~0.5 s vs ~0.8 s for 4K on a slow
mount, is ~10 MB instead of ~185 MB, and decoding it costs ~4x less CPU/GPU.
The original source is never modified.

## Picker

Switch wallpapers without editing the config or restarting Hyprland:

```bash
videowall-picker          # interactive
videowall-picker --list   # just print the scanned videos, no UI
```

Scans `~/.local/share/wallpapers/` (plus the optional `WALLPAPER_DIR=` from the
config) for `*.mp4|*.webm|*.mov|*.mkv`, dedupes by basename, and shows one row
per video with resolution, duration and size. The row of the current `VIDEO=`
(and of its generated 1080p copy) is marked with `*`.

| Key | Action |
|-----|--------|
| `Enter` | Apply: confirm, then `pkill -x mpvpaper`, persist `VIDEO=` in `~/.config/videowall/videowall.conf` and relaunch the launcher — live, no restart. |
| `Esc` / `Ctrl+C` | Exit without changes. |

Requires **fzf** (`sudo pacman -S fzf`). Run it from a terminal, or bind it in
Hyprland through a terminal emulator, e.g. `bind = SUPER, V, exec, kitty videowall-picker`.

### Preview

- With **chafa** installed (`sudo pacman -S chafa`), the right pane renders a
  real frame of the selected video (extracted with ffmpeg at half the
  duration). The pipeline is killed as soon as the selection changes.
- **Without chafa** the picker degrades to a metadata pane (name, size,
  resolution, duration, path) — still fully usable.
- Metadata (size/resolution/duration) comes from a one-time ffprobe cache at
  `~/.cache/videowall/probe-cache.json`; only changed files are re-probed, so
  the list renders instantly even on slow mounts (NTFS/4K).

### Troubleshooting

- **Preview shows only the metadata pane** — chafa is not installed, or the
  file has no readable video stream. This is the expected fallback; install
  chafa for frame previews.
- **First run is slow, later runs are instant** — that is the probe cache
  warming up. Delete `~/.cache/videowall/probe-cache.json` if you suspect stale
  entries.
- **`videowall-picker` says no wallpapers found** — drop videos into
  `~/.local/share/wallpapers/` or set `WALLPAPER_DIR=` in the config.

## Uninstall

```bash
bash uninstall.sh
```

Stops the running wallpaper and daemon, strips the autostart blocks from both
variants, removes the installed scripts/config if videowall-owned, and drops
the state marker. Generated video copies are left in place with a hint on how
to remove them.

## Troubleshooting

- **Wallpaper does not appear after login** — check
  `hyprctl monitors -j` returns at least one monitor (the launcher waits ~5 s
  and aborts otherwise), and that `VIDEO` points to an existing file.
- **Game is fullscreen but the wallpaper keeps playing** — the daemon only
  reacts to windows Hyprland reports as `fullscreen: 1` (see
  `hyprctl activewindow -j`). Borderless "fake" fullscreen that doesn't set
  Hyprland's fullscreen state won't trigger the pause.
- **Wallpaper frozen (black) after the daemon died** — a killed daemon would
  leave `mpvpaper` SIGSTOPped. The daemon traps SIGTERM/SIGINT and resumes the
  wallpaper before exiting; if it was killed with SIGKILL, recover with
  `pkill -CONT -x mpvpaper`.
- **Daemon complains about `HYPRLAND_INSTANCE_SIGNATURE`** — it must run inside
  a Hyprland session; this variable is only set there.
- **Testing scripts from a plain terminal** — Hyprland sockets live under
  `$XDG_RUNTIME_DIR/hypr/`. Start them from the session
  (e.g. via a Hyprland keybind) rather than from a separate TTY.
- **Daemon log** — `cat $XDG_RUNTIME_DIR/videowall-autopause.log` shows
  pause/resume transitions. Fork vs standard detection is logged on startup.

## Video encode tip

The 1080p faststart copy is generated automatically, using:

```bash
ffmpeg -y -v error -i <source> -vf "scale=1920:1080:flags=lanczos" -an \
    -c:v libx264 -preset veryfast -crf 22 -profile:v high -pix_fmt yuv420p \
    -movflags +faststart <output>.mp4
```

`-movflags +faststart` moves the moov atom to the front so playback starts
almost immediately; `crf 22` balances quality and size. Build the copy once
and point `VIDEO` at it to skip the conversion entirely.

## License

MIT — see [LICENSE](LICENSE).