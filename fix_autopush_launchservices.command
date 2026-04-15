#!/bin/bash
# Fix for the macOS TCC gotcha: LaunchAgent was invoking the .app's bash binary
# directly, which doesn't inherit FDA from the parent .app bundle. This rewrites
# the plist to launch via `open -W -a`, which goes through LaunchServices and
# does inherit the .app's FDA grant.
set -e

LABEL="com.ccgl.dashboard.autopush"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_PATH="$HOME/Applications/CCGL_AutoPush.app"
LOG="/tmp/ccgl_autopush.log"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ Cannot find $APP_PATH — re-run push.command first to rebuild the .app"
  exit 1
fi

echo "── Writing LaunchAgent plist to launch via 'open -W -a' ──"
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-W</string>
        <string>-g</string>
        <string>-n</string>
        <string>-a</string>
        <string>${APP_PATH}</string>
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
echo "✓ Wrote $PLIST"

echo "── Unloading old agent ──"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo "── Loading new agent ──"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "✓ Loaded"

echo "── Verifying program path ──"
launchctl print "gui/$(id -u)/${LABEL}" | grep -E "program|argument|interval" | head -10 || true

echo "── Marking log boundary ──"
echo "" >> "$LOG"
echo "════════ open -W -a fix applied at $(date '+%Y-%m-%d %H:%M:%S') ════════" >> "$LOG"

echo "── Kickstarting one test run ──"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"
sleep 5

echo "── Last 20 log lines ──"
tail -20 "$LOG" 2>/dev/null || echo "(no log yet)"

echo ""
echo "If you see '✓ pushed' WITHOUT 'Operation not permitted' above this line,"
echo "the fix worked. The agent will now fire every 2 minutes."
echo ""
echo "Press any key to close…"
read -n 1
