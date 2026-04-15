#!/bin/bash
# fix_launchagent.command — fix plist + patch .app binary with current token
PLIST="$HOME/Library/LaunchAgents/com.ccgl.dashboard.autopush.plist"
APP_BIN="$HOME/Applications/CCGL_AutoPush.app/Contents/MacOS/CCGL_AutoPush"
REPO="/Users/dangillan/ccgl_dashboard"

echo "── CCGL LaunchAgent Fix ──"
echo ""

# 1. Write corrected plist pointing to .app binary
cat > "$PLIST" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ccgl.dashboard.autopush</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/dangillan/Applications/CCGL_AutoPush.app/Contents/MacOS/CCGL_AutoPush</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ccgl_autopush.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ccgl_autopush_err.log</string>
</dict>
</plist>
PLIST
echo "✓ Plist updated → .app binary"

# 2. Patch .app binary with correct REPO path and new token
cat > "$APP_BIN" << 'SCRIPT'
#!/bin/bash
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
REPO="/Users/dangillan/ccgl_dashboard"
LOG="/tmp/ccgl_autopush.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ── autopush check" >> "$LOG"
cd "$REPO" || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: cd failed" >> "$LOG"; exit 1; }

rm -f .git/HEAD.lock .git/index.lock .git/refs/heads/main.lock 2>/dev/null

/usr/bin/git add CCGL_Finance_Dashboard.html index.html >> "$LOG" 2>&1

if /usr/bin/git diff --cached --quiet; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] nothing to commit" >> "$LOG"
else
  MSG="auto: dashboard updated $(date '+%b %-d %Y · %-I:%M %p')"
  /usr/bin/git commit -m "$MSG" >> "$LOG" 2>&1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ committed: $MSG" >> "$LOG"
fi

AHEAD=$(/usr/bin/git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "${AHEAD:-0}" -gt 0 ]; then
  GIT_TERMINAL_PROMPT=0 /usr/bin/git push >> "$LOG" 2>&1 \
    && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ pushed $AHEAD commit(s)" >> "$LOG" \
    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: push failed" >> "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] up to date" >> "$LOG"
fi
SCRIPT
chmod +x "$APP_BIN"
echo "✓ .app binary patched"

# 3. Reload LaunchAgent
launchctl unload "$PLIST" 2>/dev/null
launchctl load "$PLIST"
echo "✓ LaunchAgent reloaded (runs every 2 min)"

echo ""
echo "── Done ──"
echo "Log: tail -20 /tmp/ccgl_autopush.log"
echo ""
read -p "Press Enter to close..."
