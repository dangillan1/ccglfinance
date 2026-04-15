#!/bin/bash
REPO="/Users/dangillan/Documents/Claude/Projects/CCGL Finance"
APPS_DIR="$HOME/Applications"
APP="$APPS_DIR/CCGL_AutoPush.app"
APP_BIN="$APP/Contents/MacOS/CCGL_AutoPush"
APP_PLIST="$APP/Contents/Info.plist"
LA_PLIST="$HOME/Library/LaunchAgents/com.ccgl.dashboard.autopush.plist"

echo "=== CCGL Dashboard Push + .app Watcher Setup ==="
cd "$REPO" || { echo "ERROR: cannot find repo at $REPO"; read -p "Press Enter..."; exit 1; }

# 1. Push current changes immediately (Terminal has FDA so this works)
echo ""
echo "── Step 1: pushing pending changes ──"
rm -f .git/HEAD.lock .git/index.lock .git/refs/heads/main.lock 2>/dev/null
git add CCGL_Finance_Dashboard.html index.html
if git diff --cached --quiet; then
  echo "Nothing new to push (already current)."
else
  git commit -m "auto: dashboard updated $(date '+%b %-d %Y · %-I:%M %p')"
  git push && echo "✓ Pushed to GitHub"
fi

# 2. Remove any old cron entry
(crontab -l 2>/dev/null | grep -v "CCGL Finance.*git\|ccgl_autopush") | crontab - 2>/dev/null

# 3. Stop any existing LaunchAgent (we're rebuilding it)
echo ""
echo "── Step 2: building CCGL_AutoPush.app at ~/Applications ──"
launchctl unload "$LA_PLIST" 2>/dev/null

# 4. Build the .app bundle
mkdir -p "$APPS_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Info.plist — minimal but valid app
cat > "$APP_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CCGL_AutoPush</string>
    <key>CFBundleIdentifier</key>
    <string>com.ccgl.dashboard.autopush</string>
    <key>CFBundleName</key>
    <string>CCGL AutoPush</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Access dashboard files</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Access CCGL Finance repo for git operations</string>
</dict>
</plist>
EOF

# The actual binary — bash script that does git push
cat > "$APP_BIN" << 'EOF'
#!/bin/bash
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LOG="/tmp/ccgl_autopush.log"
REPO="/Users/dangillan/Documents/Claude/Projects/CCGL Finance"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ── check started" >> "$LOG"

cd "$REPO" || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: cd failed (need FDA on this app)" >> "$LOG"; exit 1; }

rm -f .git/HEAD.lock .git/index.lock .git/refs/heads/main.lock 2>/dev/null

/usr/bin/git add CCGL_Finance_Dashboard.html index.html >> "$LOG" 2>&1

if /usr/bin/git diff --cached --quiet; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] nothing to commit" >> "$LOG"
else
  MSG="auto: dashboard updated $(date '+%b %-d %Y · %-I:%M %p')"
  /usr/bin/git commit -m "$MSG" >> "$LOG" 2>&1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ committed: $MSG" >> "$LOG"
fi

# Push if local main is ahead of origin (covers commits made externally,
# e.g. from the Cowork sandbox which can't push directly through the proxy)
AHEAD=$(/usr/bin/git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "${AHEAD:-0}" -gt 0 ]; then
  /usr/bin/git push >> "$LOG" 2>&1 \
    && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ pushed $AHEAD commit(s)" >> "$LOG" \
    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: push failed" >> "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] up to date with origin" >> "$LOG"
fi
EOF

chmod +x "$APP_BIN"
echo "✓ Built $APP"

# 5. Install LaunchAgent that calls the .app's binary directly
echo ""
echo "── Step 3: installing LaunchAgent ──"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$LA_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ccgl.dashboard.autopush</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BIN</string>
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
EOF

launchctl load "$LA_PLIST"
echo "✓ LaunchAgent loaded"

if launchctl list | grep -q "com.ccgl.dashboard.autopush"; then
  echo "✓ CONFIRMED: com.ccgl.dashboard.autopush is active"
fi

# 6. Open System Settings to FDA pane
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ONE-TIME SETUP: Grant Full Disk Access to CCGL_AutoPush.app"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Opening System Settings → Privacy & Security → Full Disk Access"
echo ""
echo "  Steps:"
echo "  1. Click the [+] button (authenticate if asked)"
echo "  2. In the file picker, press ⌘ + Shift + G"
echo "  3. Paste this exact path:"
echo ""
echo "       $APP"
echo ""
echo "  4. Press Enter, then click Open / Add"
echo "  5. Toggle the new 'CCGL AutoPush' entry ON"
echo "  6. Close System Settings"
echo ""
echo "  Within 2 minutes, autopush starts working forever."
echo ""

# Copy the path to clipboard so user can just paste
echo -n "$APP" | pbcopy 2>/dev/null && echo "  (Path copied to clipboard — just ⌘V in the file picker)"

open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

echo ""
read -p "Press Enter when you've granted FDA (or to skip)..."

# 7. Trigger and check
echo ""
echo "── Triggering test run ──"
launchctl kickstart -k "gui/$(id -u)/com.ccgl.dashboard.autopush" 2>/dev/null
sleep 5
echo ""
echo "--- Last log entries ---"
tail -15 /tmp/ccgl_autopush.log 2>/dev/null || echo "(no log yet)"
echo ""
echo "If the log shows '✓ pushed' or 'nothing to commit' — SUCCESS."
echo "If it shows 'ERROR: cd failed (need FDA on this app)' — go back and grant FDA."
echo ""
read -p "Press Enter to close..."
