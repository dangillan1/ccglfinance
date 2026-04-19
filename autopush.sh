#!/bin/bash
# CCGL Dashboard Auto-Push Script
# Runs every 2 min via LaunchAgent com.ccgl.dashboard.autopush
# Log: /tmp/ccgl_autopush.log

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="/Users/dangillan/ccgl_dashboard"
LOG="/tmp/ccgl_autopush.log"
LOCKFILE="/tmp/ccgl_autopush.flock"

# Prevent overlapping runs — exit immediately if another cycle is active
exec 9>"$LOCKFILE"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] skip: previous cycle still running" >> "$LOG"; exit 0; }

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ── check started" >> "$LOG"

# Enter repo
cd "$REPO" || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: cd failed to $REPO" >> "$LOG"; exit 1; }

# Clear any stale git locks (all known lock files)
rm -f .git/HEAD.lock .git/index.lock .git/ORIG_HEAD.lock .git/refs/heads/main.lock .git/MERGE_HEAD.lock .git/FETCH_HEAD.lock 2>/dev/null

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

# Fetch so tracking ref is current (handles sandbox force-pushes, etc.)
/usr/bin/git fetch origin >> "$LOG" 2>&1

# Move aside any untracked files that would collide with incoming tracked files
BACKUP_DIR="/tmp/ccgl_autopush_backup"
mkdir -p "$BACKUP_DIR"
/usr/bin/git ls-tree -r origin/main --name-only 2>/dev/null | while IFS= read -r f; do
  if [ -e "$f" ] && ! /usr/bin/git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    mv -- "$f" "$BACKUP_DIR/$f" 2>/dev/null \
      && echo "[$(date '+%Y-%m-%d %H:%M:%S')] moved untracked collision: $f" >> "$LOG"
  fi
done

# Heal any divergence automatically: rebase first, fall back to merge -X ours
BEHIND=$(/usr/bin/git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
if [ "${BEHIND:-0}" -gt 0 ]; then
  if /usr/bin/git rebase origin/main >> "$LOG" 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ rebased onto origin ($BEHIND behind)" >> "$LOG"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] rebase conflicts — aborting and trying merge -X ours" >> "$LOG"
    /usr/bin/git rebase --abort >> "$LOG" 2>&1
    if /usr/bin/git merge --no-edit -X ours origin/main >> "$LOG" 2>&1; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ merged origin with -X ours (local wins)" >> "$LOG"
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: merge -X ours also failed, aborting" >> "$LOG"
      /usr/bin/git merge --abort >> "$LOG" 2>&1
    fi
  fi
fi

# Push if local main is ahead of origin
AHEAD=$(/usr/bin/git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "${AHEAD:-0}" -gt 0 ]; then
  /usr/bin/git push >> "$LOG" 2>&1 \
    && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ pushed $AHEAD commit(s)" >> "$LOG" \
    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: push failed" >> "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] up to date with origin" >> "$LOG"
fi
