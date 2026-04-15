#!/bin/bash
# Relocates the CCGL Finance git repo OUT of ~/Documents (TCC-protected) to
# ~/ccgl_dashboard (unprotected), then symlinks the original Documents path to
# the new location so Cowork mounts and existing aliases keep working.
# After this, the LaunchAgent autopush works without ANY Full Disk Access
# permission, because nothing it touches is in a protected directory.
set -e

LABEL="com.ccgl.dashboard.autopush"
OLD="$HOME/Documents/Claude/Projects/CCGL Finance"
NEW="$HOME/ccgl_dashboard"
APP_BIN="$HOME/Applications/CCGL_AutoPush.app/Contents/MacOS/CCGL_AutoPush"
LOG="/tmp/ccgl_autopush.log"

echo "── Pre-flight checks ──"
if [ ! -d "$OLD/.git" ]; then
  echo "✗ $OLD is not a git repo. Aborting."
  exit 1
fi
if [ -e "$NEW" ]; then
  echo "✗ $NEW already exists. Move it aside first or edit this script."
  exit 1
fi
if [ -L "$OLD" ]; then
  echo "✗ $OLD is already a symlink — looks like this script was already run."
  exit 1
fi

echo "── Stopping LaunchAgent ──"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo "── Copying repo to $NEW (rsync, preserves .git, no deletes) ──"
rsync -a "$OLD/" "$NEW/"
echo "✓ Copied"

echo "── Verifying new repo is healthy ──"
cd "$NEW"
git status -sb | head -3
git log --oneline -3

echo "── Renaming old location aside and creating symlink ──"
BACKUP="${OLD}.bak.$(date +%s)"
mv "$OLD" "$BACKUP"
ln -s "$NEW" "$OLD"
echo "✓ $OLD → $NEW (original moved to $BACKUP)"

echo "── Patching .app autopush binary to use new repo path ──"
if [ -f "$APP_BIN" ]; then
  /usr/bin/sed -i.orig "s|REPO=\".*\"|REPO=\"$NEW\"|" "$APP_BIN"
  echo "✓ Updated REPO in $APP_BIN"
  grep "^REPO=" "$APP_BIN"
else
  echo "⚠ Could not find $APP_BIN — you may need to re-run push.command after this"
fi

echo "── Also rewriting plist to call binary directly (no need for open -W -a since FDA is irrelevant now) ──"
cat > "$HOME/Library/LaunchAgents/${LABEL}.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${LOG}</string>
</dict>
</plist>
EOF
echo "✓ Plist rewritten"

echo "── Loading agent ──"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/${LABEL}.plist"

echo "── Marking log boundary ──"
echo "" >> "$LOG"
echo "════════ relocated to $NEW at $(date '+%Y-%m-%d %H:%M:%S') ════════" >> "$LOG"

echo "── Kickstarting test run ──"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"
sleep 4

echo "── Last 15 log lines ──"
tail -15 "$LOG" 2>/dev/null

echo ""
echo "✓ Done. Repo now lives at $NEW"
echo "  Documents path is now a symlink — Cowork mount + any aliases still work"
echo "  Look above the boundary line for ANY 'Operation not permitted'."
echo "  If clean, autopush is autonomous — no FDA, no quirks, forever."
echo ""
echo "Press any key to close…"
read -n 1
