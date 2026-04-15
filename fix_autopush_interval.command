#!/bin/bash
# Fixes the LaunchAgent that's missing StartInterval — only had RunAtLoad,
# so it fired once at load and never again. Adds StartInterval=120 (2 min),
# unloads/reloads the agent, kickstarts a test run, and tails the log.
set -e

LABEL="com.ccgl.dashboard.autopush"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_BIN="$HOME/Applications/CCGL_AutoPush.app/Contents/MacOS/CCGL_AutoPush"
LOG="/tmp/ccgl_autopush.log"

if [ ! -x "$APP_BIN" ]; then
  echo "✗ Cannot find $APP_BIN — re-run push.command first to rebuild the .app"
  exit 1
fi

echo "── Writing LaunchAgent plist with StartInterval=120 ──"
cat > "$PLIST" << EOF
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
echo "✓ Wrote $PLIST"

echo "── Unloading old agent ──"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo "── Loading new agent ──"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "✓ Loaded"

echo "── Verifying interval is set ──"
launchctl print "gui/$(id -u)/${LABEL}" | grep -E "program|state|interval|exit" || true

echo "── Kickstarting one test run ──"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"
sleep 3

echo "── Last 15 log lines ──"
tail -15 "$LOG" 2>/dev/null || echo "(no log yet)"

echo ""
echo "✓ Done. Agent will now fire every 2 minutes."
echo "Press any key to close…"
read -n 1
