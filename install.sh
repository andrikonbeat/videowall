#!/usr/bin/env bash
# videowall installer — idempotent. Safe to re-run.
#
# Installs:
#   ~/.local/share/videowall/            launcher, autopause daemon + picker
#   ~/.config/videowall/videowall.conf   config template (only if missing)
#   ~/.local/state/videowall-installed   installed marker
# plus an idempotent autostart entry for the detected Hyprland variant.
#
# Run as your normal user (never with sudo):
#   bash install.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/videowall"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/videowall"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/videowall-installed"

say()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. Dependencies ----------------------------------------------------------
MISSING=""
for dep in mpvpaper ffmpeg socat hyprctl; do
    command -v "$dep" >/dev/null 2>&1 || MISSING="$MISSING $dep"
done
if [ -n "$MISSING" ]; then
    fail "missing dependencies:$MISSING
  Install them (Arch Linux):
    sudo pacman -S ffmpeg socat        # hyprctl ships with Hyprland itself
    mpvpaper: AUR package (yay -S mpvpaper) or build from source
              https://github.com/GianniCarlo/mpvpaper
  Nothing was installed or changed. Re-run install.sh once the deps are present."
fi

# --- 2. Hyprland variant detection --------------------------------------------
# fork:   Hyprland build with the Lua config engine (version string contains _hlg_)
#         or a Lua config dir exists at ~/.config/hypr/hyprland/*.lua
# standard: upstream Hyprland, config at ~/.config/hypr/hyprland.conf
VARIANT="standard"
if hyprctl version 2>&1 | grep -q "_hlg_"; then
    VARIANT="fork"
elif [ -d "$HOME/.config/hypr/hyprland" ] && ls "$HOME/.config/hypr/hyprland"/*.lua >/dev/null 2>&1; then
    VARIANT="fork"
fi

# --- 3. Copy scripts ----------------------------------------------------------
mkdir -p "$INSTALL_DIR"
install -m 755 "$REPO_DIR/src/videowall" "$INSTALL_DIR/videowall"
install -m 755 "$REPO_DIR/src/videowall-autopause" "$INSTALL_DIR/videowall-autopause"
install -m 755 "$REPO_DIR/src/videowall-picker" "$INSTALL_DIR/videowall-picker"
say "installed scripts -> $INSTALL_DIR/"
command -v fzf >/dev/null 2>&1 \
    || say "note: fzf not found - install it to use videowall-picker (sudo pacman -S fzf)"

# --- 4. Config template (never overwrite user edits) --------------------------
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_DIR/videowall.conf" ]; then
    say "config already exists (kept): $CONFIG_DIR/videowall.conf"
else
    cp "$REPO_DIR/src/videowall.conf" "$CONFIG_DIR/videowall.conf"
    say "created config: $CONFIG_DIR/videowall.conf  (edit VIDEO= before first use)"
fi

# --- 5. Autostart wiring (idempotent, marker-based) ---------------------------
MARKER='===== videowall ====='
AUTOSTART_FILE=""

if [ "$VARIANT" = "fork" ]; then
    EXECS_LUA="$HOME/.config/hypr/hyprland/execs.lua"
    AUTOSTART_FILE="$EXECS_LUA"
    [ -f "$EXECS_LUA" ] || fail "fork variant detected but $EXECS_LUA not found."

    if grep -qF -- "$MARKER" "$EXECS_LUA"; then
        say "autostart already wired in $EXECS_LUA (marker found, skipping)."
    elif grep -q 'hl\.on("hyprland\.start", function(' "$EXECS_LUA"; then
        # Insert the block as the first statements of the hyprland.start handler.
        awk -v dir="$INSTALL_DIR" '
            /hl\.on\("hyprland\.start", function\(/ && !done {
                print
                print "-- ===== videowall ====="
                print "hl.exec_cmd(\"bash " dir "/videowall\")"
                print "hl.exec_cmd(\"bash " dir "/videowall-autopause\")"
                print "-- ===== end videowall ====="
                done = 1
                next
            }
            { print }
        ' "$EXECS_LUA" > "$EXECS_LUA.tmp" &&
        mv "$EXECS_LUA.tmp" "$EXECS_LUA" ||
            fail "failed to edit $EXECS_LUA (no changes applied)."
        say "wired autostart into $EXECS_LUA (hyprland.start handler)."
    else
        fail "no hl.on(\"hyprland.start\", function() handler found in $EXECS_LUA."
    fi
else
    HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
    AUTOSTART_FILE="$HYPR_CONF"
    if grep -qF -- "$MARKER" "$HYPR_CONF" 2>/dev/null; then
        say "autostart already wired in $HYPR_CONF (marker found, skipping)."
    else
        mkdir -p "$(dirname "$HYPR_CONF")"
        cat >> "$HYPR_CONF" <<EOF
# ===== videowall =====
exec-once = bash $INSTALL_DIR/videowall
exec-once = bash $INSTALL_DIR/videowall-autopause
# ===== end videowall =====
EOF
        say "wired autostart into $HYPR_CONF (exec-once)."
    fi
fi

# --- 6. Installed marker ------------------------------------------------------
mkdir -p "$STATE_DIR"
printf 'videowall installed %s\nvariant: %s\nautostart: %s\n' \
    "$(date '+%F %T')" "$VARIANT" "$AUTOSTART_FILE" > "$STATE_FILE"

# --- Summary ------------------------------------------------------------------
say ""
say "videowall installed successfully."
say "  variant  : $VARIANT"
say "  autostart: $AUTOSTART_FILE (active at the next Hyprland restart)"
say "  config   : $CONFIG_DIR/videowall.conf"
say ""
say "Next steps:"
say "  1. Edit $CONFIG_DIR/videowall.conf and set VIDEO= to your wallpaper file."
say "  2. Restart Hyprland, or start it right now with:"
say "       bash $INSTALL_DIR/videowall &"
say "       bash $INSTALL_DIR/videowall-autopause &"
say ""
say "Uninstall any time with: bash $(basename "${BASH_SOURCE[0]}")'s sibling uninstall.sh"