#!/bin/bash
# Writes the corrected autopush script into the .app binary.
# Adds ahead-of-origin push so commits made from Cowork sandbox get pushed
# even when there's no new file diff to stage.
APP_BIN="$HOME/Applications/CCGL_AutoPush.app/Contents/MacOS/CCGL_AutoPush"
LOG="/tmp/ccgl_autopush.log"
REPO="$HOME/ccgl_dashboard"
LABEL="com.ccgl.dashboard.autopush"

echo "── Writing corrected binary to $APP_BIN ──"
cat > "$APP_BIN" << 'SCRIPT'
#!/bin/bash
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LOG="/tmp/ccgl_autopush.log"
REPO="__REPO__"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ── check started" >> "$LOG"

cd "$REPO" || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: cd failed to $REPO" >> "$LOG"; exit 1; }

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
  /usr/bin/git push >> "$LOG" 2>&1 \
    && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ pushed $AHEAD commit(s)" >> "$LOG" \
    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: push failed" >> "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] up to date with origin" >> "$LOG"
fi
SCRIPT

# Substitute real REPO path
sed -i '' "s|__REPO__|$REPO|g" "$APP_BIN"
chmod +x "$APP_BIN"
echo "✓ Binary written"

echo "── Reloading LaunchAgent ──"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/${LABEL}.plist"
echo "✓ Reloaded"

echo "── Kickstarting test run ──"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
sleep 5

echo "── Last 15 log lines ──"
tail -15 "$LOG"

echo ""
echo "Press any key to close…"
read -n 1
