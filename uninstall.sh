#!/usr/bin/env bash
# videowall uninstaller — reverses everything install.sh did. Idempotent.
#
# Removes:
#   - running wallpaper instances (mpvpaper + the autopause daemon)
#   - autostart marker blocks from execs.lua (fork) and hyprland.conf (standard)
#   - ~/.local/share/videowall/            (only if videowall-owned)
#   - ~/.config/videowall/                 (only if videowall-owned)
#   - ~/.local/state/videowall-installed   state marker
#
# Generated 1080p copies under ~/.local/share/wallpapers/ are left in place
# (they may be shared with other tools); a hint to remove them is printed.
#
# Run as your normal user (never with sudo):
#   bash uninstall.sh

set -u

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/videowall"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/videowall"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/videowall-installed"
EXECS_LUA="$HOME/.config/hypr/hyprland/execs.lua"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

say() { printf '%s\n' "$*"; }

# --- 1. Stop running instances -------------------------------------------------
# Resume first (in case the wallpaper is SIGSTOPped), then stop everything.
pkill -CONT -x mpvpaper 2>/dev/null
if pkill -x mpvpaper 2>/dev/null; then
    say "stopped mpvpaper (video wallpaper)"
fi
if pkill -f 'videowall-autopause' 2>/dev/null; then
    say "stopped videowall-autopause daemon"
fi

# --- 2. Strip autostart marker blocks (both variants; marker-based, idempotent)
strip_autostart() {
    local f="$1"
    [ -f "$f" ] || return 0
    if grep -qF -- '===== videowall =====' "$f"; then
        sed -i '/===== videowall =====/,/===== end videowall =====/d' "$f" \
            && say "removed autostart block from $f"
    fi
}
strip_autostart "$EXECS_LUA"
strip_autostart "$HYPR_CONF"

# If our block was the only content, drop the leftover empty file.
[ -s "$HYPR_CONF" ] 2>/dev/null || rm -f "$HYPR_CONF"

# --- 3. Remove installed files (only if videowall-owned) -----------------------
if [ -d "$INSTALL_DIR" ]; then
    if [ -f "$INSTALL_DIR/videowall" ] || [ -f "$INSTALL_DIR/videowall-autopause" ]; then
        rm -rf "$INSTALL_DIR" && say "removed $INSTALL_DIR"
    else
        say "skipped $INSTALL_DIR: does not look videowall-owned (no videowall scripts inside)"
    fi
fi
if [ -d "$CONFIG_DIR" ]; then
    if [ -f "$CONFIG_DIR/videowall.conf" ]; then
        rm -rf "$CONFIG_DIR" && say "removed $CONFIG_DIR"
    else
        say "skipped $CONFIG_DIR: no videowall.conf found, leaving it"
    fi
fi

# --- 4. State marker ------------------------------------------------------------
if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE" && say "removed state marker $STATE_FILE"
fi

# --- 5. Report leftovers ---------------------------------------------------------
say ""
say "videowall uninstalled."
say "  Left in place (removable by hand if you no longer want them):"
say "    ~/.local/share/wallpapers/*-1080p.mp4  (generated wallpaper copies)"
say ""
say "The video wallpaper in the CURRENT session ends at the next Hyprland"
say "restart if it was not stopped above."