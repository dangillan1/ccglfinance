#!/bin/bash
# CCGL Dashboard Auto-Push Script
# Runs every 2 min via LaunchAgent com.ccgl.dashboard.autopush
# Log: /tmp/ccgl_autopush.log

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="/Users/dangillan/ccgl_dashboard"
LOG="/tmp/ccgl_autopush.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ── check started" >> "$LOG"

# Enter repo
cd "$REPO" || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: cd failed to $REPO" >> "$LOG"; exit 1; }

# Clear any stale locks
rm -f .git/HEAD.lock .git/index.lock .git/refs/heads/main.lock 2>/dev/null

# Stage target files
/usr/bin/git add CCGL_Finance_Dashboard.html index.html >> "$LOG" 2>&1

# Commit if anything staged
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
